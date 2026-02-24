require "process"

module Crybot
  module Crysh
    module Rofi
      Log = ::Log.for("crysh.rofi")

      # Show rofi dialog to confirm command execution
      # Returns the command to execute (may be edited by user), or nil if cancelled
      def self.confirm(command : String) : String?
        # Prepare rofi message
        message = "Run this command?\n\n#{command}"

        # rofi options with edit capability
        # Using -theme-str to set larger font for better readability
        rofi_args = [
          "-dmenu",
          "-p", "crysh",
          "-mesg", message,
          "-format", "s",       # Only return the selected item
          "-selected-row", "0", # Pre-select "Run"
          "-l", "3",            # Show 3 lines
        ]

        # Create the options list
        options = "Run\nEdit\nCancel"

        Log.debug { "Showing rofi confirmation for command: #{command}" }

        # Run rofi and capture the selection
        process = Process.new(
          "rofi",
          rofi_args,
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Inherit
        )

        # Write options to rofi
        process.input.puts(options)
        process.input.close

        # Read the selection
        selection = process.output.gets.try(&.strip)

        # Wait for rofi to finish
        process.wait

        if selection.nil?
          Log.info { "No selection made (rofi was cancelled)" }
          return nil
        end

        case selection
        when "Run"
          Log.info { "User selected: Run" }
          command
        when "Edit"
          Log.info { "User selected: Edit" }
          edit_command(command)
        when "Cancel"
          Log.info { "User selected: Cancel" }
          nil
        else
          # User made a custom selection or typed something
          if selection.empty?
            Log.info { "Empty selection, treating as Cancel" }
            nil
          else
            Log.info { "User entered custom command: #{selection}" }
            selection
          end
        end
      rescue e : Exception
        Log.error { "Rofi error: #{e.message}" }
        # If rofi fails, log the error and return nil (don't run the command)
        nil
      end

      # Allow user to edit the command using $EDITOR or rofi's edit mode
      private def self.edit_command(command : String) : String?
        editor = ENV["EDITOR"]?

        if editor.nil?
          # No EDITOR set, use rofi's simple prompt editing
          edit_with_rofi(command)
        else
          edit_with_editor(command, editor)
        end
      end

      # Use rofi's dmenu mode for simple inline editing
      private def self.edit_with_rofi(command : String) : String?
        message = "Edit command then press Enter:\n(Current: #{command})"

        process = Process.new(
          "rofi",
          ["-dmenu", "-p", "Edit", "-mesg", message],
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Inherit
        )

        # Pre-fill with current command
        process.input.puts(command)
        process.input.close

        edited = process.output.gets.try(&.strip)
        process.wait

        if edited.nil? || edited.empty?
          Log.info { "Edit cancelled, using original command" }
          command
        else
          Log.info { "Command edited to: #{edited}" }
          edited
        end
      end

      # Use external editor for full editing experience
      private def self.edit_with_editor(command : String, editor : String) : String?
        # Create a temp file
        temp_file = File.tempfile("crysh_edit_", ".sh")

        begin
          # Write command to temp file
          File.write(temp_file.path, command)

          # Parse editor command and arguments
          # Handles both "editor" and "editor -flags" formats
          editor_parts = editor.split(" ")
          editor_cmd = editor_parts[0]
          editor_args = editor_parts[1..]? || [] of String
          editor_args << temp_file.path

          # Open editor
          editor_process = Process.new(
            editor_cmd,
            editor_args,
            input: Process::Redirect::Inherit,
            output: Process::Redirect::Inherit,
            error: Process::Redirect::Inherit
          )
          editor_process.wait

          # Read edited command
          edited = File.read(temp_file.path).strip

          if edited.empty?
            Log.info { "Edit resulted in empty command, using original" }
            command
          else
            Log.info { "Command edited with #{editor}" }
            edited
          end
        ensure
          temp_file.delete
        end
      end
    end
  end
end
