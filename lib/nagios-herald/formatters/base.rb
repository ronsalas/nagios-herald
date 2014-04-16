# base formatter
require 'app_conf'
require 'tmpdir'
require 'nagios-herald/logging' # needed?
require 'nagios-herald/util'
require 'nagios-herald/formatter_loader'
require 'ap'

module NagiosHerald
  class Formatter
    #include NagiosHerald::Logging  # needed?
    include NagiosHerald::Util

    # @sandbox is the place to save attachments, possibly a tempdir
    attr_accessor :sandbox
    attr_accessor :tag

    # when instansiated, load all formatters
    def initialize
      @attachments = []
      @html = ""
      #@nagios_url = options.nagiosurl    # SOON
      @sandbox  = nil
      @state_type = get_nagios_var("NAGIOS_SERVICESTATE") != "" ? "SERVICE" : "HOST"
      @tag  = ""
      @text = ""

    end

    def self.formatters
      @@formatters ||= {}
    end

    # when subclassed formatters are instantiated, add them to the @@formatters hash
    # the key is the downcased and snake_cased name of the class file (i.e. check_disk)
    # and the value is the actual class (i.e. CheckDisk) so that we can easily
    # instantiate formatters when we know the formatter name
    def self.inherited(subclass)
      puts "#{subclass} inherited from #{self.name}!" # debug
      subclass_base_name = subclass.name.split('::').last
      puts "subclass base name: #{subclass_base_name}"    # debug
      subclass_base_name.gsub!(/[A-Z]/) { |s| "_" + s } # replace uppercase with underscore and lowercase
      subclass_base_name.downcase!
      subclass_base_name.sub!(/^_/, "")   # strip the leading underscore
      puts "snake_case: #{subclass_base_name}"    # debug
      formatters[subclass_base_name] = subclass
      ap formatters   # debug
    end

    ## methods to generate content

    # concatenate text
    def add_text(text)
      @text += text
    end

    # concatenate html
    def add_html(html)
      @html += html
    end

    # add moar attachments (like images)
    def add_attachment(path)
      @attachments << path
    end

    def format_line_break
      add_text "\n"
      add_html "<br>"
    end

    def start_section(*section_style_args)
      if ! section_style_args.nil?
         style = section_style_args.join(';')
         add_html "<div style='#{style}'>"
      end
    end

    def end_section
      add_html "</div>"
    end

    def format_host_info
      notification_type = get_nagios_var("NAGIOS_NOTIFICATIONTYPE")
      hostname          = get_nagios_var("NAGIOS_HOSTNAME")
      service_desc      = get_nagios_var("NAGIOS_SERVICEDESC")
      add_text "Host: #{hostname} "
      add_html "<br><b>Host</b>: #{hostname} "
      if !service_desc.nil? and !service_desc.empty?
        add_text "Service: #{service_desc}\n"
        add_html "<b>Service</b>: #{service_desc}<br/>"
      else
        # we need a trailing newline if no service description
        format_line_break
      end
      format_line_break
    end

    def format_state_info
      state         = get_nagios_var("NAGIOS_#{@state_type}STATE")
      duration      = get_nagios_var("NAGIOS_#{@state_type}DURATION")
      last_duration = get_nagios_var("NAGIOS_LAST#{@state_type}STATE")
      attempts      = get_nagios_var("NAGIOS_#{@state_type}ATTEMPT")
      max_attempts  = get_nagios_var("NAGIOS_MAX#{@state_type}ATTEMPTS")
      add_text "State is now: #{state} for #{duration} (was #{last_duration}) after #{attempts} / #{max_attempts} checks\n"
      if state.eql? 'OK' or state.eql? 'UP'
          add_html "State is now: <b>#{state}</b> for <b>#{duration}</b> (was #{last_duration}) after <b>#{attempts} / #{max_attempts}</b> checks<br/>"
      else
          add_html "State is now: <b><font style='color:red'>#{state}</font></b> for <b>#{duration}</b> (was #{last_duration}) after <b>#{attempts} / #{max_attempts}</b> checks<br/>"
      end
      format_line_break
    end

    def format_notification_info
      date   = get_nagios_var("NAGIOS_LONGDATETIME")
      number = get_nagios_var("NAGIOS_NOTIFICATIONNUMBER")
      add_text "Notification sent at: #{date} (notification number #{number})\n\n"
      add_html "Notification sent at: #{date} (notification number #{number})<br><br>"
    end

    # checks plugin's output
    def format_additional_info
      output = get_nagios_var("NAGIOS_#{@state_type}OUTPUT")
      if !output.nil? and !output.empty?
        add_text "Additional info: #{unescape_text(output)}\n\n"
        add_html "<b>Additional info</b>: #{output}<br><br>"
      end
    end

    def format_notes
      notes = get_nagios_var("NAGIOS_#{@state_type}NOTES")
      if !notes.nil? and !notes.empty?
        add_text "Notes: #{unescape_text(notes)}\n\n"
        add_html "<b>Notes</b>: #{notes}<br><br>"
      end

      notes_url = get_nagios_var("NAGIOS_#{@state_type}NOTESURL")
      if !notes_url.nil? and !notes_url.empty?
        add_text "Notes URL: #{notes_url}\n\n"
        add_html "<b>Notes URL</b>: #{notes_url}<br><br>"
      end
    end

    # checks plugin's long output
    def format_additional_details
      long_output = get_nagios_var("NAGIOS_LONG#{@state_type}OUTPUT")
      if !long_output.nil? and !long_output.empty?
        add_text "Additional Details: #{unescape_text(long_output)}\n"
        add_html "<b>Additional Details</b>: <pre>#{unescape_text(long_output)}</pre><br><br>"
      end
    end

    def format_action_url
      action_url = get_nagios_var("NAGIOS_#{@state_type}ACTIONURL")
      if !action_url.nil? and !action_url.empty?
        add_text "Action URL: #{action_url}\n\n"
        add_html "<b>Action URL</b>: #{action_url}<br><br>"
      end
    end

    def format_state_detail
      if @state_type == "SERVICE"
        format_notes
        format_additional_details
      end
      format_line_break
    end

    def format_short_state_detail
      output   = get_nagios_var("NAGIOS_#{@state_type}OUTPUT")
      add_text = "#{output}\n"
      add_html = "#{output}<br>"
    end

    def format_recipients_email_link
      hostname      = get_nagios_var("NAGIOS_HOSTNAME")
      if @state_type == "SERVICE"
        service_desc  = get_nagios_var("NAGIOS_SERVICEDESC")
        subject = "#{hostname} - #{service_desc}"
      else
        subject = "#{hostname}"
      end

      recipients      = get_nagios_var("NAGIOS_NOTIFICATIONRECIPIENTS")
      return if recipients.nil?
      recipients_list   = recipients.split(',')
      recipients_mail   = recipients_list.map {|n| n + "@etsy.com"}
      recipients_mail_str = recipients_mail.join(',')
      add_text "Sent to #{recipients}\n"
      add_html %Q(Sent to <a href="mailto:#{recipients_mail_str}?subject=#{subject}">#{recipients}</a><br>)
    end

    def format_ack_info
      date    = get_nagios_var("NAGIOS_LONGDATETIME")
      author    = get_nagios_var("NAGIOS_#{@state_type}ACKAUTHOR")
      comment   = get_nagios_var("NAGIOS_#{@state_type}ACKCOMMENT")
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")

      add_text "At #{date} #{author}"
      add_html "At #{date} #{author}"

      if @state_type == "SERVICE"
        desc = get_nagios_var("NAGIOS_SERVICEDESC")
        add_text " acknowledged #{desc} on #{hostname}.\n\n"
        add_html " acknowledged #{desc} on #{hostname}.<br><br>"
      else
        add_text " acknowledged #{hostname}.\n\n"
        add_html " acknowledged #{hostname}.<br><br>"

      end
      add_text "Comment: #{comment}" if comment
      add_html "Comment: #{comment}" if comment
    end

    def format_short_ack_info
      author    = get_nagios_var("NAGIOS_#{@state_type}ACKAUTHOR")
      comment   = get_nagios_var("NAGIOS_#{@state_type}COMMENT")
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")

      add_text "#{author}  ack'd "
      add_html "#{author}  ack'd "

      if @state_type == "SERVICE"
        desc = get_nagios_var("NAGIOS_SERVICEDESC")
        add_text "#{desc} on #{hostname}.\n"
        add_html "#{desc} on #{hostname}.<br>"
      else
        add_text "#{hostname}.\n"
        add_html "#{hostname}.<br>"

      end
      add_text "Comment: #{comment}" if comment
      add_html "Comment: #{comment}" if comment
    end

    def format_alert_ack_url
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")
      service_desc = get_nagios_var("NAGIOS_SERVICEDESC")

      if service_desc != ""
        url = "#{@nagios_url}?cmd_typ=34&host=#{hostname}&service=#{service_desc}"
      else
        url = "#{@nagios_url}?cmd_typ=33&host=#{hostname}"
      end
      url = URI.escape(url)
      add_text "Acknowledge this alert: #{url}\n"
      add_html "Acknowledge this alert: #{url}<br>"
    end

    def generate_section(name, *section_style_args)
      # let's get (start|end)_section from default_formatter
      # and strip calls to methods via @formatter
      @formatter.start_section(*section_style_args)
      @formatter.end_section
    end

    def generate_problem_content
      if @pager_mode
        generate_section("format_short_state_detail")
        @formatter.tag = ""
      else
        @formatter.tag = "ALERT"
        generate_section("format_host_info")
        generate_section("format_state_info")
        generate_section("format_additional_info")
        generate_section("format_action_url")
        generate_section("format_state_detail") # format_notes and format_additional_details for services
        generate_section("format_recipients_email_link")
        generate_section("format_notification_info")
        generate_section("format_alert_ack_url")
      end
    end

    def generate_recovery_content
      @formatter.tag = "OK"
      if @pager_mode
        generate_section("format_short_state_detail")
      else
        generate_section("format_host_info", "color:green")
        generate_section("format_state_info", "color:green")
        generate_section("format_additional_info", "color:green")
        generate_section("format_action_url", "color:green")
        generate_section("format_state_detail", "color:green") # format_notes and format_additional_details for services
        generate_section("format_recipients_email_link")
        generate_section("format_notification_info")
      end
    end

    def generate_ack_content
      @formatter.tag = "ACK"
      if @pager_mode
        generate_section("format_short_ack_info")
      else
        generate_section("format_host_info")
        generate_section("format_ack_info")
      end
    end

    def generate_content(nagios_notification_type)
      case nagios_notification_type
        when "PROBLEM", "FLAPPINGSTART"
          generate_problem_content
        when "RECOVERY", "FLAPPINGSTOP"
          generate_recovery_content
        when "ACKNOWLEDGEMENT"
          generate_ack_content
        else
          $stderr.puts "Invalid Nagios notification type!\nExpecting something like PROBLEM or RECOVERY"
          exit 1
        end
    end

    def get_sandbox_path
      @sandbox = Dir.mktmpdir if @sandbox.nil?
      return @sandbox
    end

    def clean_sandbox
      FileUtils.remove_entry @sandbox if  File.directory?(@sandbox)
    end

  end
end

