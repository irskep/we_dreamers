window.WD = window.WD or {}

_showUsernamePrompt = (callback, isRepeat = false) ->
  $el = $("
    <div class='username-prompt-container'>
      <form class='username-prompt'>
        <label>Pick a username:</label>
        <input maxlength=60 name='username' autofocus>
      </form>
    </div>
  ".trim()).appendTo($('body'))
  if isRepeat
    $("<div>(The one you tried was taken)</div>").insertAfter($el.find('input'))
  $form = $el.find('form')
  $form.on 'submit', (e) ->
    value = $el.find('input').val()
    if value
      $el.remove()
      callback(value)
    e.preventDefault()
    false


WD.ensureUser = (callback, isRepeat = false) ->
  fbUsers = fb.child('users')
  if localStorage.getItem('username')
    username = localStorage.getItem('username')
    fbUsers.child(username).once 'value', (snapshot) ->
      data = snapshot.val()
      unless data
        data = 
          username: username
          color:
            r: _.random(50, 255)
            g: _.random(50, 255)
            b: _.random(50, 255)
          position:
            x: 0
            y: 0
        fbUsers.child(username).set(data)
      callback(username)
  else
    f = (username) =>
      fbUsers.child(username).once 'value', (snapshot) ->
        if snapshot.val()
          WD.ensureUser(callback, true)
        else
          # win!
          data =
            username: username
            color:
              r: _.random(50, 255)
              g: _.random(50, 255)
              b: _.random(50, 255)
            position:
              x: 0
              y: 0
          fbUsers.child(username).set(data)
          localStorage.setItem('username', username)
          callback(username)
    _showUsernamePrompt(f, isRepeat)


WD.showStats = (player) =>
  $el = $("<div class='stats'>").appendTo('body')
  template = _.template """
    <div class="help-button"><a href="javascript:void(0);">Help</a></div>
    <div class="stat-color stat-r"><div class="color-key mono">r</div></div>
    <div class="stat-color stat-g"><div class="color-key mono">g</div></div>
    <div class="stat-color stat-b"><div class="color-key mono">b</div></div>
    <div class="color-key-instructions">
      Press <span class="mono">r</span>, <span class="mono">g</span>,
      and <span class="mono">b</span> to mix what color your next room will be.
      Your dot shows your next room's color.
      <hr>
    </div>
    <div class="stat-level">Level <%- level %></div>
    <% if (roomsDug) { %>
      <div class="stat-rooms-dug">Rooms dug: <%- roomsDug %></div>
    <% } %>
    <% if (notesLeft) { %>
      <div class="stat-notes-left">Notes written: <%- notesLeft %></div>
    <% } %>
    <% if (stampsStamped) { %>
      <div class="stat-stamps-stamped">Stamps: <%- stampsStamped %></div>
    <% } %>
    <% if (level == 1) { %>
      <div class="level-instructions">Dig rooms to reach level 2.</div>
    <% } %>
    <% if (level == 2) { %>
      <div class="level-instructions">
        Leave notes on rooms you dug to reach level 3.
     </div>
    <% } %>
    <% if (level >= 3) { %>
      <div class="stamp-instructions">Press J and K to stamp</div>
    <% } %>
  """

  player.statsUpdates.onValue (data) ->
    data = _.clone player.stats
    data.level = parseInt(player.level, 10)
    data.notesLeft = parseInt(player.stats.notesLeft, 10) or 0
    data.stampsStamped = parseInt(player.stats.stampsStamped, 10) or 0
    $el.html(template(data))
    _.each ['r', 'g', 'b'], (k) ->
      $el.find(".stat-#{k}").css
        'margin-top': (player.maxBucket() - data[k]) / 2
        'height': data[k] / 2

  $el.on 'click', 'a', ->
    WD.showHelp()


WD.showRoom = (player) =>
  $el = $("<div class='room-info-container'>").appendTo('body')
  template = _.template """
    <div class="room-info">
      <% if (player.username == creator && player.level > 1) { %>
        <form class="fortune-form">
          <textarea name="fortune"><%- fortuneText %></textarea>
          <input type="submit" value="Leave note">
        </form>
      <% } else { %>
        <div class="text">
          <% if (fortuneText) { %>
            <span class="creator"><%- creator %> says,</span>
            &ldquo;<%- fortuneText %>&rdquo;
          <% } else { %>
            Dug by <%- creator %>
          <% } %>
        </span>
      <% } %>
    </div>
  """

  update = (room) ->
    data = _.clone(room)
    data.player = player
    data.fortuneText = data.fortuneText or ''
    $el.html(template(data))

  player.currentRoomProperty.onValue (room) ->
    return unless room
    $el.asEventStream('submit').takeUntil(player.currentRoomProperty.changes())
      .onValue (e) ->
        e.preventDefault()
        isNew = !room.fortuneText
        room.fb.child('fortuneText').set($el.find('textarea').val())
        if isNew
          player.cleanStats()
          player.fb.child('stats/notesLeft').set(
            (player.stats.notesLeft or 0) + 1)
        false

  player.currentRoomProperty.sampledBy(player.statsUpdates)
    .merge(player.currentRoomProperty).onValue (room) ->
      return unless room
      update(room)

      room.updates.takeUntil(player.currentRoomProperty.changes()).onValue ->
        update(room)

WD.showHelp = ->
  $el = $("""
    <div class="wtf-container">
      <div class="wtf">
        <h1>Here's what's up.</h1>
        <p>
          This is an abstract multiplayer art piece. Things you can do:
        </p>
        <ol>
          <li>Move with the arrow keys or <tt>WASD</tt>.</li>
          <li>Harvest color with <tt>space</tt>.</li>
          <li>Dig out new rooms by bumping into walls. You need color to do
            this. The new room will be the color of your dot, which is affected
            by the color in your bucket.</li>
          <li>Dump color with <tt>r</tt>, <tt>g</tt>, and <tt>b</tt> (or
            <tt>1</tt>, <tt>2</tt>, and <tt>3</tt>) to change the color of
            your dot.</li>
          <li>Leave notes on rooms (if you are level 2).</li>
          <li>Put down big block letters (if you are level 3).</li>
        </ol>
        <p>
          Watch the sidebar for how to level up.
        </p>
        <p>
          Enjoy yourself...and be at peace.
        </p>
      </div>
    </div>
  """).appendTo('body')
  _.defer ->
    $('body').one 'click', ->
      $el.remove()
