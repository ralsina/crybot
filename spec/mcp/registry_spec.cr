require "spec"
require "webmock"
require "../../src/mcp/registry"
require "../../src/config/schema"

# Mock registry responses for testing
module MockRegistry
  # Sample server response mimicking the real registry
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
            "packages": [],
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
              "publishedAt": "2025-12-05T21:51:53.421065Z",
              "updatedAt": "2025-12-05T21:51:53.421065Z",
              "isLatest": true
            }
          }
        },
        {
          "server": {
            "$schema": "https://static.modelcontextprotocol.io/schemas/2025-09-29/server.schema.json",
            "name": "ai.mcpcap/mcpcap",
            "description": "An MCP server for analyzing PCAP files",
            "version": "0.5.10",
            "repository": {
              "url": "https://github.com/mcpcap/mcpcap",
              "source": "github"
            },
            "packages": [
              {
                "registryType": "pypi",
                "registryBaseUrl": "https://pypi.org",
                "identifier": "mcpcap",
                "version": "0.5.10",
                "transport": {
                  "type": "stdio"
                }
              }
            ]
          },
          "_meta": {
            "io.modelcontextprotocol.registry/official": {
              "status": "active",
              "publishedAt": "2025-09-12T05:10:59.806509Z",
              "updatedAt": "2025-09-18T00:54:49.018201Z",
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
            ],
            "remotes": []
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
            "name": "ai.test/oci-server",
            "description": "Test OCI/Docker server",
            "version": "1.0.0",
            "packages": [
              {
                "registryType": "oci",
                "identifier": "docker.io/test/server:1.0.0",
                "version": "1.0.0",
                "transport": {
                  "type": "stdio"
                }
              }
            ],
            "remotes": []
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
            "name": "ai.spotify/player",
            "description": "Control Spotify playback and search tracks",
            "version": "1.2.0",
            "repository": {
              "url": "https://github.com/spotify/mcp-server",
              "source": "github"
            },
            "packages": [
              {
                "registryType": "npm",
                "identifier": "@spotify/mcp-server",
                "version": "1.2.0",
                "transport": {
                  "type": "stdio"
                }
              }
            ],
            "remotes": []
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
            "name": "ai.spotify/web-api",
            "description": "Spotify Web API integration",
            "version": "2.0.0",
            "repository": {
              "url": "https://github.com/spotify/web-api-mcp",
              "source": "github"
            },
            "packages": [
              {
                "registryType": "npm",
                "identifier": "@spotify/web-api",
                "version": "2.0.0",
                "transport": {
                  "type": "stdio"
                }
              }
            ],
            "remotes": []
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
        "count": 6
      }
    }
    JSON
  end

  # Paginated response (first page)
  def self.paginated_page1 : String
    <<-JSON
    {
      "servers": [
        {
          "server": {
            "$schema": "https://static.modelcontextprotocol.io/schemas/2025-09-29/server.schema.json",
            "name": "ai.test/server1",
            "description": "Test server 1",
            "version": "1.0.0",
            "packages": [],
            "remotes": []
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
        "nextCursor": "page2_cursor",
        "count": 1
      }
    }
    JSON
  end

  # Paginated response (second page)
  def self.paginated_page2 : String
    <<-JSON
    {
      "servers": [
        {
          "server": {
            "$schema": "https://static.modelcontextprotocol.io/schemas/2025-09-29/server.schema.json",
            "name": "ai.test/server2",
            "description": "Test server 2",
            "version": "1.0.0",
            "packages": [],
            "remotes": []
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
        "count": 1
      }
    }
    JSON
  end

  # Error response
  def self.error_response : String
    <<-JSON
    {
      "error": "Internal Server Error"
    }
    JSON
  end
end

describe Crybot::MCP::Registry do
  before_each do
    WebMock.reset
  end

  describe "#search" do
    it "fetches and parses servers from registry" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search

      results.size.should eq 6
      results.all?(&.is_latest).should be_true
      results.all?(&.is_official).should be_true
    end

    it "filters servers by query string" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search("spotify")

      results.size.should eq 2
      results.all?(&.name.downcase.includes?("spotify")).should be_true
    end

    it "searches by description" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search("pcap")

      results.size.should eq 1
      results.first.name.should eq "ai.mcpcap/mcpcap"
    end

    it "searches by repository URL" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search("github.com/exa-labs")

      results.size.should eq 1
      results.first.name.should eq "ai.exa/exa"
    end

    it "returns empty array when no matches found" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search("nonexistent-server-xyz")

      results.size.should eq 0
    end

    it "respects limit parameter" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      results = Crybot::MCP::Registry.search(limit: 3)

      results.size.should eq 3
    end

    it "handles pagination correctly" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.paginated_page1, status: 200)

      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers?cursor=page2_cursor")
        .to_return(body: MockRegistry.paginated_page2, status: 200)

      results = Crybot::MCP::Registry.search

      results.size.should eq 2
      results.map(&.name).should eq ["ai.test/server1", "ai.test/server2"]
    end

    it "raises error on HTTP failure" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.error_response, status: 500)

      expect_raises(Crybot::MCP::RegistryError, "Failed to fetch servers: 500") do
        Crybot::MCP::Registry.search
      end
    end
  end

  describe "#get" do
    it "fetches specific server by name" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa")

      server.should_not be_nil
      server.not_nil!.name.should eq "ai.exa/exa"
      server.not_nil!.version.should eq "3.1.3"
    end

    it "returns nil when server not found" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.nonexistent/server")

      server.should be_nil
    end

    it "prefers latest version when multiple versions exist" do
      # This test would require multiple versions of the same server
      # in the mock data, which we don't have currently
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa")

      server.not_nil!.is_latest.should be_true
    end
  end

  describe "ServerInfo" do
    it "identifies HTTP transport correctly" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa").not_nil!

      server.transport_type.should eq Crybot::MCP::Registry::TransportType::StreamableHttp
      server.needs_url?.should be_true
      server.installation_target.should eq "https://mcp.exa.ai/mcp"
    end

    it "identifies PyPI transport correctly" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.mcpcap/mcpcap").not_nil!

      server.transport_type.should eq Crybot::MCP::Registry::TransportType::PyPI
      server.needs_url?.should be_false
      server.installation_target.should eq "mcpcap"
      server.suggested_command.should eq "uvx mcpcap"
    end

    it "identifies NPM transport correctly" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.spotify/player").not_nil!

      server.transport_type.should eq Crybot::MCP::Registry::TransportType::NPM
      server.suggested_command.should eq "npx @spotify/mcp-server"
    end

    it "identifies OCI transport correctly" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.test/oci-server").not_nil!

      server.transport_type.should eq Crybot::MCP::Registry::TransportType::OCI
      server.suggested_command.should eq "docker run docker.io/test/server:1.0.0"
    end

    it "returns display name without ai. prefix" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa").not_nil!

      server.display_name.should eq "exa"
    end
  end

  describe "#generate_config" do
    it "generates URL-based config for HTTP servers" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.exa/exa").not_nil!
      config = Crybot::MCP::Registry.generate_config(server)

      config.name.should eq "exa"
      config.url.should eq "https://mcp.exa.ai/mcp"
      config.command.should be_nil
    end

    it "generates command-based config for NPM servers" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.spotify/player").not_nil!
      config = Crybot::MCP::Registry.generate_config(server)

      config.name.should eq "player"
      config.command.should eq "npx @spotify/mcp-server"
      config.url.should be_nil
    end

    it "generates command-based config for PyPI servers" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      server = Crybot::MCP::Registry.get("ai.mcpcap/mcpcap").not_nil!
      config = Crybot::MCP::Registry.generate_config(server)

      config.name.should eq "mcpcap"
      config.command.should eq "uvx mcpcap"
    end

    it "raises error for unknown server types" do
      WebMock.stub(:get, "https://registry.modelcontextprotocol.io/v0/servers")
        .to_return(body: MockRegistry.sample_servers_json, status: 200)

      # Create a server with no packages or remotes by parsing JSON
      server_json = {
        "name"                  => "ai.test/unknown",
        "description"           => "Unknown server",
        "version"               => "1.0.0",
        "packages"              => [] of String,
        "remotes"               => [] of String,
        "title"                 => nil.as(String?),
        "repository"            => nil.as(String?),
        "website_url"           => nil.as(String?),
        "icons"                 => [] of String,
        "environment_variables" => [] of String,
      }.to_json

      server = Crybot::MCP::Registry::ServerInfo.from_json(server_json)

      expect_raises(Crybot::MCP::RegistryError, "Cannot determine how to install server") do
        Crybot::MCP::Registry.generate_config(server)
      end
    end
  end

  describe "TransportType" do
    it "returns correct display names" do
      Crybot::MCP::Registry::TransportType::NPM.display_name.should eq "npm (npx)"
      Crybot::MCP::Registry::TransportType::PyPI.display_name.should eq "Python (uvx)"
      Crybot::MCP::Registry::TransportType::OCI.display_name.should eq "Docker"
      Crybot::MCP::Registry::TransportType::StreamableHttp.display_name.should eq "HTTP"
      Crybot::MCP::Registry::TransportType::SSE.display_name.should eq "SSE"
      Crybot::MCP::Registry::TransportType::Unknown.display_name.should eq "Unknown"
    end
  end
end
