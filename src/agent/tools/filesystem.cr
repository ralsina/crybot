require "file_utils"
require "./base"

module Crybot
  module Agent
    module Tools
      class ReadFileTool < Tool
        def name : String
          "read_file"
        end

        def description : String
          "Read the contents of a file. Returns the file contents as a string."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "path" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The path to the file to read"),
              }),
            }),
            "required" => JSON::Any.new(["path"].map { |string| JSON::Any.new(string) }),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          path = get_string_arg(args, "path")
          return "Error: path is required" if path.empty?

          begin
            File.read(path)
          rescue e : File::NotFoundError
            "Error: File not found: #{path}"
          rescue e : Exception
            "Error: #{e.message}"
          end
        end
      end

      class WriteFileTool < Tool
        def name : String
          "write_file"
        end

        def description : String
          "Write content to a file. Creates parent directories if they don't exist. Overwrites existing files."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "path" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The path to the file to write"),
              }),
              "content" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The content to write to the file"),
              }),
            }),
            "required" => JSON::Any.new(["path", "content"].map { |string| JSON::Any.new(string) }),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          path = get_string_arg(args, "path")
          content = get_string_arg(args, "content")

          return "Error: path is required" if path.empty?
          return "Error: content is required" if content.nil?

          STDERR.puts "[WriteFile] Writing to: #{path}"

          begin
            dir = File.dirname(path)
            Dir.mkdir_p(dir) unless Dir.exists?(dir)
            File.write(path, content)
            STDERR.puts "[WriteFile] Successfully wrote to: #{path}"
            "Successfully wrote to #{path}"
          rescue e : Exception
            STDERR.puts "[WriteFile] Error: #{e.message}"
            # Don't swallow the exception - let tool_runner_impl handle it
            # This allows proper Landlock access denied handling
            raise e
          end
        end
      end

      class EditFileTool < Tool
        def name : String
          "edit_file"
        end

        def description : String
          "Replace occurrences of old_content with new_content in a file. Can limit number of replacements."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "path" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The path to the file to edit"),
              }),
              "old_content" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The content to replace"),
              }),
              "new_content" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The replacement content"),
              }),
              "count" => JSON::Any.new({
                "type"        => JSON::Any.new("integer"),
                "description" => JSON::Any.new("Maximum number of replacements to make (0 = all)"),
              }),
            }),
            "required" => JSON::Any.new(["path", "old_content", "new_content"].map { |string| JSON::Any.new(string) }),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          path = get_string_arg(args, "path")
          old_content = get_string_arg(args, "old_content")
          new_content = get_string_arg(args, "new_content")
          count = get_int_arg(args, "count", 0)

          return "Error: path is required" if path.empty?
          return "Error: old_content is required" if old_content.empty?
          return "Error: new_content is required" if new_content.nil?

          begin
            content = File.read(path)

            if count > 0
              content = content.sub(old_content, new_content)
            else
              content = content.gsub(old_content, new_content)
            end

            File.write(path, content)
            "Successfully edited #{path}"
          rescue e : File::NotFoundError
            "Error: File not found: #{path}"
          rescue e : Exception
            "Error: #{e.message}"
          end
        end
      end

      class ListDirTool < Tool
        def name : String
          "list_dir"
        end

        def description : String
          "List the contents of a directory. Returns a list of file and directory names with type indicators."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "path" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The path to the directory to list (default: current directory)"),
              }),
            }),
            "required" => JSON::Any.new([] of JSON::Any),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          path = get_string_arg(args, "path", ".")

          begin
            entries = Dir.children(path)
            result = [] of String

            entries.each do |entry|
              full_path = File.join(path, entry)
              if Dir.exists?(full_path)
                result << "#{entry}/"
              else
                result << entry
              end
            end

            result.join("\n")
          rescue e : File::NotFoundError
            "Error: Directory not found: #{path}"
          rescue e : Exception
            "Error: #{e.message}"
          end
        end
      end
    end
  end
end
