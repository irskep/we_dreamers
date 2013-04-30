window.WD = window.WD or {}

window.fb = (new Firebase('https://we-dreamers.firebaseio.com/LD26'))

# hax
WD.useFirefoxGradients = false
WD.useSafariGradients = false

class WD.Clock

  constructor: ->
    @tick = new Bacon.Bus()

    raf = window.requestAnimationFrame
    unless raf
      raf = window.mozRequestAnimationFrame
      WD.useFirefoxGradients = true
    unless raf
      raf = window.webkitRequestAnimationFrame
      WD.useSafariGradients = true
    animate = (t) =>
      @t = t
      @tick.push(t)
      raf(animate)
    raf(animate)

  now: -> @t

class WD.GameController

  constructor: (@$el) ->
    window.gc = this
    @$el.append($('<div class="wd-inner"></div>'))
    @$worldContainer = $('<div class="room-container"></div>')
      .appendTo(@$el.find('.wd-inner'))
      .css
        position: 'absolute'
        overflow: 'visible'

    @moveWorldContainer('x', - WD.GRID_SIZE / 2)
    @moveWorldContainer('y', - WD.GRID_SIZE / 2)

    @$interactiveContainer = $('<div class="wd-interactive"></div>')
      .appendTo(@$worldContainer)
    @viewOffset = V2(0, 0)
    @rooms = {}
    @doors = {}
    @chunks = {}

  addRoom: (room) ->
    @rooms[room.hash()] = room
    @$worldContainer.append(room.$el)

    room.fb.child('walls').on 'child_changed', (snapshot) =>
      data = snapshot.val()
      keys = _.keys(data).sort()
      if keys.length > 2 and data[_.last(keys)] == @player.username
        @excavate(room, Vector2.fromString(snapshot.name()))

  addDoor: (door) ->
    @doors[door.hash1()] = [] unless door.hash1() of @doors
    @doors[door.hash2()] = [] unless door.hash2() of @doors
    @doors[door.hash1()].push(door)
    @doors[door.hash2()].push(door)
    @$worldContainer.append(door.$el)

  initBaseData: =>
    fbChunkZero = fb.child('chunks').child(WD.chunkForPoint(V2(0, 0)))
    fbRooms = fbChunkZero.child('rooms')
    fbDoors = fbChunkZero.child('doors')
    fbRoomZero = fbRooms.child(V2(0, 0).toString())
    fbRoomZero.once 'value', (snapshot) =>
      center = V2(0, 0)
      left = V2(-1, 0)
      right = V2(1, 0)
      top = V2(0, -1)
      bottom = V2(0, 1)

      unless snapshot.val()
        console.log 'initializing rooms'
        fbRoomZero.set({
           position: center,
           color: WD.colorFromHSV(120, 75, 100),
           lastHarvested: 0,
           creator: "Steve"})
        fbRooms.child(top.toString()).set({
           position: top,
           color: WD.colorFromHSV(60, 75, 100),
           lastHarvested: 0,
           creator: "Steve"})
        fbRooms.child(bottom.toString()).set({
           position: bottom,
           color: WD.colorFromHSV(0, 75, 100),
           lastHarvested: 0,
           creator: "Steve"})
        fbRooms.child(left.toString()).set({
           position: left,
           color: WD.colorFromHSV(180, 75, 100),
           lastHarvested: 0,
           creator: "Steve"})
        fbRooms.child(right.toString()).set({
           position: right,
           color: WD.colorFromHSV(240, 75, 100),
           lastHarvested: 0,
           creator: "Steve"})

        _.each [
          [center, right], [left, center], [top, center], [center, bottom]
        ], ([a, b]) ->
          fbDoors.child(a.toString() + b.toString()).set
            room1: a
            room2: b
            type: 'basic'

  run: ->
    @roomsLoadedBus = new Bacon.Bus()
    @roomsAreLoaded = @roomsLoadedBus.toProperty(false)
    @players = {}
    @$worldContainer.hide()

    soundManager.setup
      # where to find flash audio SWFs, as needed
      url: 'swf/',
      # optional: prefer HTML5 over Flash for MP3/MP4
      preferFlash: false,
      debugMode: false,
      onready: ->
        soundManager.createSound
          id: 'bonk'
          url: 'audio/bonk.wav'
          multiShot: true
          autoLoad: true

        _.each WD.SOUNDS, (s) ->
          soundManager.createSound
            id: s
            url: "audio/#{s}.mp3"
            multiShot: true
            autoLoad: true

    WD.ensureUser (username) =>
      WD.showHelp()
      $loadingEl = $("<div class='status-message'>Loading...</div>").appendTo(@$el)
      @username = username
      @clock = new WD.Clock()
      @initBaseData()
      @player = new WD.Player(@clock, username, this)
      @interactify(@player)
      @$interactiveContainer.append(@player.$el)

      fb.child('online_users').on 'child_added', (snapshot) =>
        data = snapshot.val()
        return if data == username
        @players[data] = new WD.Player(@clock, data, this)
        @players[data].midBonks.onValue ->
          soundManager.play('bonk', volume: 20)
        @$interactiveContainer.append(@players[data].$el)

      fb.child('online_users').on 'child_removed', (snapshot) =>
        data = snapshot.val()
        return if data == username or not (data of @players)
        @players[data].remove()

      @load($loadingEl)

  load: ($loadingEl) ->
    anyRoomsLoaded = false
    stillLoadingRooms = false
    checkRoomsLoaded = =>
      if anyRoomsLoaded and not stillLoadingRooms
        $loadingEl.remove()
        @roomsLoadedBus.push(true)
        return
      stillLoadingRooms = false
      setTimeout checkRoomsLoaded, 200
    checkRoomsLoaded()

    loadRoom = (snapshot) =>
      data = snapshot.val()
      @addRoom new WD.Room(
        V2(data.position.x, data.position.y),
        data.color, data.lastHarvested, this)
      stillLoadingRooms = true
      anyRoomsLoaded = true

    fb.child('chunks/(0, 0)/rooms').on 'child_added', (snapshot) =>
      data = snapshot.val()
      @addRoom new WD.Room(
        V2(data.position.x, data.position.y),
        data.color, data.lastHarvested, this)
      stillLoadingRooms = true
      anyRoomsLoaded = true

    fb.child('chunks/(0, 0)/doors').on 'child_added', (snapshot) =>
      data = snapshot.val()
      @addDoor new WD.Door(
        V2(data.room1.x, data.room1.y),
        V2(data.room2.x, data.room2.y), data.type)
      stillLoadingRooms = true
      anyRoomsLoaded = true

    @player.fb.child('position').once 'value', (snapshot) =>
      setTimeout (=> @$worldContainer.show()), 400

  interactify: (player) ->
    fbOnline = fb.child('online_users').child(player.username)
    fbOnline.set(player.username)
    fbOnline.onDisconnect().remove()

    player.$el.find('.wd-player-username').remove()

    @$worldContainer.asEventStream('click', '.wd-room').onValue (e) =>
      gridPoint = V2($(e.target).data('gridX'), $(e.target).data('gridY'))
      @clickRoom(@roomAtPoint(gridPoint))

    player.$el.addClass('you')

    keyboardToDirection = (keyName, vector) =>
      nextRoom = => @adjacentRoom(player.currentRoom, vector)
      @clock.tick.filter(player.isStill).filter(WD.keyboard.isDown(keyName))
        .onValue =>
          if nextRoom()
            player.fb.child('position').set(nextRoom().gridPoint)
      WD.keyboard.downs(keyName)
        .filter(player.isStill)
        .filter(player.canBonk)
        .onValue =>
          unless nextRoom()
            player.fb.child('bonk').set(vector)
            player.fb.child('bonk').set(null)
            player.midBonks.take(1).onValue (dGridPoint) =>
              @weaken(player.currentRoom, dGridPoint)

    keyboardToDirection('left', V2(-1, 0))
    keyboardToDirection('right', V2(1, 0))
    keyboardToDirection('up', V2(0, -1))
    keyboardToDirection('down', V2(0, 1))
    keyboardToDirection('a', V2(-1, 0))
    keyboardToDirection('d', V2(1, 0))
    keyboardToDirection('w', V2(0, -1))
    keyboardToDirection('s', V2(0, 1))

    WD.keyboard.downs('space').filter(player.isStill).onValue _.throttle(
      (=> @harvest(player.currentRoom)), 500)

    _.each player.positionProperties, (property, k) =>
      property.filter(player.isBonking.not()).onValue (v) =>
        @moveWorldContainer(k, -v)

    WD.keyboard.downs('j').filter(player.isStill).onValue =>
      @stamp(player.currentRoom, true)

    WD.keyboard.downs('k').filter(player.isStill).onValue =>
      @stamp(player.currentRoom, false)

    _.each ['r', 'g', 'b'], (k, i) =>
      WD.keyboard.downs(k)
        .merge(WD.keyboard.downs('' + (i + 1)))
        .onValue =>
          @player.fb.child('stats').child(k)
            .set(Math.max(@player.stats[k] - 10, 0))

    fbRoomsDug = player.fb.child('stats/roomsDug')
    level2Listener = (snapshot) =>
      return unless player.loaded
      if player.level >= 2
        fbRoomsDug.off('value', level2Listener) 
        return
      if snapshot.val() >= 6
        player.fb.child('level').set(2)
    fbRoomsDug.on 'value', level2Listener

    fbNotesLeft = player.fb.child('stats/notesLeft')
    level3Listener = (snapshot) =>
      return unless player.loaded
      fbRoomsDug.off('value', level3Listener) if player.level >= 3
      return unless player.level == 2
      if snapshot.val() >= 4
        player.fb.child('level').set(3)
    fbNotesLeft.on 'value', level3Listener

    WD.showStats(player)
    WD.showRoom(player)

    player.arrivedRoomProperty.filter(_.identity).onValue (room) =>
      $('.current-room').removeClass('current-room')
      room.$el.addClass('current-room')

    player.arrivedRoomProperty.filter(_.identity)
      .map((room) -> WD.colorToSoundId(room.color))
      .skipDuplicates()
      .onValue (key) -> soundManager.play(key, volume: 50)

    player.midBonks.onValue ->
      soundManager.play('bonk')

  moveWorldContainer: (k, v) =>
    @$worldContainer.css({x: 'left', y: 'top'}[k], v)

  clickRoom: (room) ->
    console.log 'you clicked', room

  roomAtPoint: (p) -> @rooms[p.toString()]

  adjacentRoom: (room, dGridPoint) ->
    p2 = room.gridPoint.add(dGridPoint)
    return false unless p2.toString() of @rooms
    return false unless _.find(@doors[room.hash()], (door) ->
      door.other(room.gridPoint).equals(p2)
    )
    return @roomAtPoint(p2)

  weaken: (room, dGridPoint) ->
    fb.child('chunks/(0, 0)/rooms')
      .child(room.hash())
      .child('walls')
      .child(dGridPoint.toString())
      .push(@player.username)

  excavate: (room, dGridPoint) ->
    return unless @player.canBonk()
    fbChunkZero = fb.child('chunks').child(WD.chunkForPoint(V2(0, 0)))
    fbRooms = fbChunkZero.child('rooms')
    fbDoors = fbChunkZero.child('doors')

    newPoint = room.gridPoint.add(dGridPoint)

    unless newPoint.toString() of @rooms
      newColor = WD.saturate(@player.stats)
      channelTotal = newColor.r + newColor.g + newColor.b
      _.each ['r', 'g', 'b'], (k) =>
        @player.stats[k] -= (newColor[k] / channelTotal) * WD.BONK_AMOUNT
        @player.stats[k] = Math.max(@player.stats[k], 0)

      @player.cleanStats()
      @player.fb.child('stats').set(@player.stats)

      @player.fb.child('stats/roomsDug').set(@player.stats.roomsDug + 1)

      fbRooms.child(newPoint.toString()).set
        position: newPoint
        color: newColor
        lastHarvested: 0
        creator: @player.username

    unless @adjacentRoom(room, dGridPoint)
      if dGridPoint.x + dGridPoint.y > 1
        fbDoors.child(room.hash() + newPoint.toString()).set
          room1: room.gridPoint
          room2: newPoint
          type: 'basic'
      else
        fbDoors.child(newPoint.toString() + room.hash()).set
          room1: newPoint
          room2: room.gridPoint
          type: 'basic'
      @player.cleanStats()
      _.each ['r', 'g', 'b'], (k) =>
        @player.stats[k] -= WD.BONK_AMOUNT / 2
        @player.stats[k] = Math.max(@player.stats[k], 0)
        @player.fb.child('stats').set(@player.stats)

  harvest: (room) ->
    return unless _.find(['r', 'g', 'b'], (k) =>
      @player.stats[k] < @player.maxBucket()
    )
    value = room.currentValue()
    room.fb.child('lastHarvested').set(WD.time())
    @player.cleanStats()
    _.each ['r', 'g', 'b'], (k) =>
      value[k] *= (65 + @player.level * 5)
      @player.fb.child('stats').child(k).set(
        Math.max(
          Math.min(@player.stats[k] + value[k], @player.maxBucket()), 0))

  stamp: (room, forward = true) ->
    nextKey = @player.lastStampKey
    if room.stamp
      if forward
        nextKey = WD.nextStampKey(room.stamp.key)
      else
        nextKey = WD.prevStampKey(room.stamp.key)
    else
      @player.cleanStats()
      @player.fb.child('stats/stampsStamped').set(
        (@player.stats.stampsStamped or 0) + 1)
    @player.lastStampKey = nextKey
    room.fb.child('stamp').set(WD.stamp(nextKey))
