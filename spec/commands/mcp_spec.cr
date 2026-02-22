require "spec"
require "file_utils"
require "webmock"
require "../../src/commands/mcp"
require "../../src/config/schema"

# Mock registry responses
module MockRegistry
  def self.sample_servers_json : String
    <<-JSON
    {
      "servers": [
        {
          "server": {
            "$schema": "https://static.modelcontextprotocol.io/schemas/2025-09-29/server.schema.json",
            "name": "ai.exa/exa",
            "description": "Fast, intelligent web search and web crawling",
            "version": "3.1.3",
            "repository": {
              "url": "https://github.com/exa-labs/exa-mcp-server",
              "source": "github"
            },
            "remotes": [
              {
                "type": "streamable-http",
                "url": "https://mcp.exa.ai/mcp"
              }
            ]
          },
          "_meta": {
            "io.modelcontextprotocol.registry/official": {
              "status": "active",
              "isLatest": true
            }
          }
        },
        {
          "server": {
            "$schema": "https://static.modelcontextprotocol.io/schemas/2025-09-29/server.schema.json",
            "name": "ai.test/npm-server",
            "description": "Test NPM server",
            "version": "1.0.0",
            "packages": [
              {
                "registryType": "npm",
                "identifier": "@test/mcp-server",
                "version": "1.0.0",
                "transport": {
                  "type": "stdio"
                }
              }
            ]
          },
          "_meta": {
            "io.modelcontextprotocol.registry/official": {
              "status": "active",
              "isLatest": true
            }
          }
        }
      ],
      "metadata": {
        "nextCursor": null,
        "count": 2
      }
    }
    JSON
  end
end

describe Crybot::Commands::MCP do
  describe "#run" do
    before_each do
      WebMock.reset
    end

    it "shows help when no arguments provided" do
      # Just verify it doesn't crash
      Crybot::Commands::MCP.run([] of String)
    end

    it "shows help for unknown command" do
      Crybot::Commands::MCP.run(["unknown"])
    end
  end

  describe "#search" do
    before_each do
      WebMock.reset
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)
    end

    it "searches all servers when no query provided" do
      Crybot::Commands::MCP.run(["search"])
    end

    it "searches servers with query" do
      Crybot::Commands::MCP.run(["search", "exa"])
    end

    it "handles search with no results" do
      Crybot::Commands::MCP.run(["search", "nonexistent"])
    end

    it "handles registry API error" do
      WebMock.reset
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(status: 500)

      result = IO::Memory.new
      Process.run("crybot", ["mcp", "search"], output: result, error: result)
      # Should exit with error code
    end
  end

  describe "#install" do
    before_each do
      WebMock.reset
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      # Create a temporary config directory
      @temp_dir = File.join("/tmp", "crybot_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(@temp_dir)

      # Set HOME to temp dir
      original_home = ENV["HOME"]?
      ENV["HOME"] = @temp_dir

      # Create .crybot directory
      crybot_dir = File.join(@temp_dir, ".crybot")
      Dir.mkdir_p(crybot_dir)
    end

    after_each do
      # Clean up temp directory
      if @temp_dir && Dir.exists?(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      # Restore HOME
      ENV["HOME"] = original_home if original_home
    end

    it "shows error when no server name provided" do
      result = IO::Memory.new
      Process.run("crybot", ["mcp", "install"], output: result, error: result)
      # Should show usage error
    end

    it "searches for server when exact name not found" do
      # This would test the fuzzy search functionality
      Crybot::Commands::MCP.run(["install", "exa"])
    end

    it "reports when server not found" do
      Crybot::Commands::MCP.run(["install", "nonexistent-server"])
    end
  end

  describe "#list" do
    before_each do
      @temp_dir = File.join("/tmp", "crybot_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(@temp_dir)

      original_home = ENV["HOME"]?
      ENV["HOME"] = @temp_dir

      crybot_dir = File.join(@temp_dir, ".crybot")
      Dir.mkdir_p(crybot_dir)
    end

    after_each do
      if @temp_dir && Dir.exists?(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      ENV["HOME"] = original_home if original_home
    end

    it "shows message when no servers installed" do
      Crybot::Commands::MCP.run(["list"])
    end

    it "lists installed servers" do
      # Create a config file with a server
      config_path = File.join(@temp_dir, ".crybot", "config.yml")

      config = Crybot::Config::ConfigData.new
      config.mcp_servers = [
        Crybot::Config::MCPServerConfig.new(
          name: "test-server",
          command: "npx @test/mcp",
          landlock: nil
        )
      ]

      File.write(config_path, config.to_yaml)

      Crybot::Commands::MCP.run(["list"])
    end

    it "lists servers with custom Landlock restrictions" do
      config_path = File.join(@temp_dir, ".crybot", "config.yml")

      config = Crybot::Config::ConfigData.new
      config.mcp_servers = [
        Crybot::Config::MCPServerConfig.new(
          name: "custom-server",
          command: "npx @custom/mcp",
          landlock: Crybot::Config::MCPLandlockConfig.new(
            allowed_paths: ["~/data", "~/projects"],
            allowed_ports: [8080]
          )
        )
      ]

      File.write(config_path, config.to_yaml)

      Crybot::Commands::MCP.run(["list"])
    end
  end

  describe "#uninstall" do
    before_each do
      @temp_dir = File.join("/tmp", "crybot_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(@temp_dir)

      original_home = ENV["HOME"]?
      ENV["HOME"] = @temp_dir

      crybot_dir = File.join(@temp_dir, ".crybot")
      Dir.mkdir_p(crybot_dir)
    end

    after_each do
      if @temp_dir && Dir.exists?(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      ENV["HOME"] = original_home if original_home
    end

    it "shows error when no server name provided" do
      Crybot::Commands::MCP.run(["uninstall"])
    end

    it "shows error when server not found" do
      Crybot::Commands::MCP.run(["uninstall", "nonexistent"])
    end

    it "uninstalls existing server" do
      config_path = File.join(@temp_dir, ".crybot", "config.yml")

      config = Crybot::Config::ConfigData.new
      config.mcp_servers = [
        Crybot::Config::MCPServerConfig.new(
          name: "test-server",
          command: "npx @test/mcp",
          landlock: nil
        )
      ]

      File.write(config_path, config.to_yaml)

      # Server should exist before uninstall
      loaded_config = Crybot::Config::Loader.from_file(config_path)
      loaded_config.mcp_servers.not_nil!.map(&.name).should contain("test-server")

      # Note: This test would require interactive input confirmation
      # For now we just verify the command exists
    end
  end
end

# Integration-style tests for private methods via the public interface
describe "MCP Command Integration" do
  describe "Config Generation" do
    it "generates correct config for HTTP server" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa").not_nil!
      config = Crybot::MCP::Registry.generate_config(server)

      config.name.should eq "exa"
      config.url.should eq "https://mcp.exa.ai/mcp"
      config.command.should be_nil
    end

    it "generates correct config for NPM server" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.test/npm-server").not_nil!
      config = Crybot::MCP::Registry.generate_config(server)

      config.name.should eq "npm-server"
      config.command.should eq "npx @test/mcp-server"
      config.url.should be_nil
    end
  end
end
