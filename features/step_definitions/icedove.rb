def icedove_app
  Dogtail::Application.new('Icedove')
end

def icedove_main
  # The main window title depends on context so without regexes it
  # will be hard to find it, but it so happens that it is always the
  # first frame of Icedove, so we do not have to be specific.
  icedove_app.child(roleName: 'frame')
end

def icedove_wizard
  icedove_app.child('Mail Account Setup', roleName: 'frame')
end

def icedove_inbox
  folder_view = icedove_main.child($config['Icedove']['address'],
                                   roleName: 'table row').parent
  folder_view.children(roleName: 'table row', recursive: false).find do |e|
    e.name.match(/^Inbox( .*)?$/)
  end
end

When /^I start Icedove$/ do
  workaround_pref_lines = [
    # When we generate a random subject line it may contain one of the
    # keywords that will make Icedove show an extra prompt when trying
    # to send an email. Let's disable this feature.
    'pref("mail.compose.attachment_reminder", false);'
  ]
  workaround_pref_lines.each do |line|
    $vm.file_append('/etc/icedove/pref/icedove.js ', line)
  end
  step 'I start "Icedove" via the GNOME "Internet" applications menu'
  icedove_main
end

When /^I have not configured an email account$/ do
  conf_path = "/home/#{LIVE_USER}/.icedove/profile.default/prefs.js"
  if $vm.file_exist?(conf_path)
    icedove_prefs = $vm.file_content(conf_path).chomp
    assert(!icedove_prefs.include?('mail.accountmanager.accounts'))
  end
end

Then /^I am prompted to setup an email account$/ do
  icedove_wizard
end

Then /^I cancel setting up an email account$/ do
  icedove_wizard.button('Cancel').click
end

Then /^I open Icedove's Add-ons Manager$/ do
  icedove_main.button('AppMenu').click
  icedove_main.child('Add-ons', roleName: 'menu item').click
  @icedove_addons = icedove_app.child(
    'Add-ons Manager - Icedove Mail/News', roleName: 'frame'
  )
end

Then /^I click the extensions tab$/ do
  @icedove_addons.child('Extensions', roleName: 'list item').click
end

Then /^I see that only the (.+) addons are enabled in Icedove$/ do |addons|
  expected_addons = addons.split(/, | and /)
  actual_addons =
    @icedove_addons.child('TorBirdy', roleName: 'label')
    .parent.parent.children(roleName: 'list item', recursive: false)
    .map { |item| item.name }
  expected_addons.each do |addon|
    result = actual_addons.find { |e| e.start_with?(addon) }
    assert_not_nil(result)
    actual_addons.delete(result)
  end
  assert_equal(0, actual_addons.size)
end

When /^I go into Enigmail's preferences$/ do
  $vm.focus_window('Icedove')
  @screen.type("a", Sikuli::KeyModifier.ALT)
  icedove_main.child('Preferences', roleName: 'menu item').click
  @enigmail_prefs = icedove_app.dialog('Enigmail Preferences')
end

When /^I enable Enigmail's expert settings$/ do
  @enigmail_prefs.button('Display Expert Settings and Menus').click
end

Then /^I click Enigmail's (.+) tab$/ do |tab_name|
  @enigmail_prefs.child(tab_name, roleName: 'page tab').click
end

Then /^I see that Enigmail is configured to use the correct keyserver$/ do
  keyservers = @enigmail_prefs.child(
    'Specify your keyserver(s):', roleName: 'entry'
  ).text
  assert_equal('hkps://hkps.pool.sks-keyservers.net', keyservers)
end

Then /^I see that Enigmail is configured to use the correct SOCKS proxy$/ do
  gnupg_parameters = @enigmail_prefs.child(
    'Additional parameters for GnuPG', roleName: 'entry'
  ).text
  assert_not_nil(
    gnupg_parameters['--keyserver-options http-proxy=socks5h://127.0.0.1:9050']
  )
end

Then /^I see that Torbirdy is configured to use Tor$/ do
  icedove_main.child(roleName: 'status bar')
    .child('TorBirdy Enabled:    Tor', roleName: 'label')
end

When /^I enter my email credentials into the autoconfiguration wizard$/ do
  icedove_wizard.child('Email address:', roleName: 'entry')
    .typeText($config['Icedove']['address'])
  icedove_wizard.child('Password:', roleName: 'entry')
    .typeText($config['Icedove']['password'])
  icedove_wizard.button('Continue').click
  # This button is shown if and only if a configuration has been found
  try_for(120) { icedove_wizard.button('Done') }
end

Then /^the autoconfiguration wizard's choice for the (incoming|outgoing) server is secure (.+)$/ do |type, protocol|
  type = type.capitalize + ':'
  assert_not_nil(
    icedove_wizard.child(type, roleName: 'entry').text
      .match(/^#{protocol},[^,]+, (SSL|STARTTLS)$/)
  )
end

When /^I fetch my email$/ do
  account = icedove_main.child($config['Icedove']['address'],
                               roleName: 'table row')
  account.click
  icedove_main = icedove_app.child("#{$config['Icedove']['address']} - Icedove Mail/News", roleName: 'frame')

  icedove_main.child('Mail Toolbar', roleName: 'tool bar')
    .button('Get Messages').click
  try_for(120) do
    begin
      icedove_main.child(roleName: 'status bar', retry: false)
        .child(roleName: 'progress bar', retry: false)
      false
    rescue
      true
    end
  end
end

When /^I accept the (?:autoconfiguration wizard's|manual) configuration$/ do
  # The password check can fail due to bad Tor circuits.
  retry_tor do
    try_for(120) do
      begin
        # Spam the button, even if it is disabled (while it is still
        # testing the password).
        icedove_wizard.button('Done').click
        false
      rescue
        true
      end
    end
  end
  # The account isn't fully created before we fetch our mail. For
  # instance, if we'd try to send an email before this, yet another
  # wizard will start, indicating (incorrectly) that we do not have an
  # account set up yet.
  step 'I fetch my email'
end

When /^I select the autoconfiguration wizard's (IMAP|POP3) choice$/ do |protocol|
  if protocol == 'IMAP'
    choice = 'IMAP (remote folders)'
  else
    choice = 'POP3 (keep mail on your computer)'
  end
  icedove_wizard.child(choice, roleName: 'radio button').click
end

When /^I select manual configuration$/ do
  icedove_wizard.button('Manual config').click
end

When /^I alter the email configuration to use (.*) over a hidden services$/ do |protocol|
  case protocol.upcase
  when 'IMAP', 'POP3'
    entry_name = 'Incoming:'
  when 'SMTP'
    entry_name = 'Outgoing:'
  else
    raise "Unknown mail protocol '#{protocol}'"
  end
  entry = icedove_wizard.child(entry_name, roleName: 'entry')
  entry.text = ''
  entry.typeText($config['Icedove']["#{protocol.downcase}_hidden_service"])
end

When /^I send an email to myself$/ do
  icedove_main.child('Mail Toolbar', roleName: 'tool bar').button('Write').click
  compose_window = icedove_app.child('Write: (no subject)')
  compose_window.child('To:', roleName: 'autocomplete').child(roleName: 'entry')
    .typeText($config['Icedove']['address'])
  # The randomness of the subject will make it easier for us to later
  # find *exactly* this email. This makes it safe to run several tests
  # in parallel.
  @subject = "Automated test suite: #{random_alnum_string(32)}"
  compose_window.child('Subject:', roleName: 'entry')
    .typeText(@subject)
  compose_window = icedove_app.child("Write: #{@subject}")
  compose_window.child('about:blank', roleName: 'document frame')
    .typeText('test')
  compose_window.child('Composition Toolbar', roleName: 'tool bar')
    .button('Send').click
  try_for(120) do
    not compose_window.exist?
  end
end

Then /^I can find the email I sent to myself in my inbox$/ do
  recovery_proc = Proc.new { step 'I fetch my email' }
  retry_tor(recovery_proc) do
    icedove_inbox.click
    filter = icedove_main.child('Filter these messages <Ctrl+Shift+K>',
                                roleName: 'entry')
    filter.typeText(@subject)
    hit_counter = icedove_main.child('1 message')
    inbox_view = hit_counter.parent
    message_list = inbox_view.child(roleName: 'table')
    the_message = message_list.children(roleName: 'table row').find do |message|
      # The message will be cropped in the list, so we cannot search
      # for the full message.
      message.name.start_with?("Automated test suite:")
    end
    assert_not_nil(the_message)
    # Let's clean up
    the_message.click
    inbox_view.button('Delete').click
  end
end

Then /^my Icedove inbox is non-empty$/ do
  icedove_inbox.click
  # The button is located on the first row in the message list, the
  # one that shows the column labels (Subject, From, ...).
  message_list = icedove_main.child('Select columns to display',
                                    roleName: 'push button')
                 .parent.parent
  visible_messages = message_list.children(recursive: false,
                                           roleName: 'table row')
  # The first element is the column label row, which is not a message,
  # so let's remove it.
  visible_messages.shift
  assert(visible_messages.size > 0)
end
