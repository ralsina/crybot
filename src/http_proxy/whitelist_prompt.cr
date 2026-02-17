require "log"
require "process"
require "../config/loader"
require "../landlock_socket"

module HttpProxy
  # Rofi prompt handler for domain access decisions
  module WhitelistPrompt
    # Prompt user for domain access decision via rofi
    #
    # Returns: :allow, :deny, :allow_once

    def self.prompt(domain : String) : Symbol
      # Build rofi prompt message
      message = "🔒 HTTP Proxy - Domain Access Request\n\n"
      message += "Domain: #{domain}\n\n"
      message += "Allow this domain for current and future requests?\n\n"
      message += "Options:\n"
      message += "  Allow - Allow this domain (add to whitelist)\n"
      message += "  Once Only - Allow for this session only\n"
      message += "  Deny - Block this domain request\n\n"

      # Show rofi prompt
      result = IO::Memory.new

      status = Process.run(
        "rofi",
        ["-dmenu", "-mesg", message, "-i", "-p", "Allow,Deny", "Once Only"],
        input: IO::Memory.new(""),
        output: result
      )

      unless status.success?
        Log.error { "Rofi prompt failed" }
        return :deny
      end

      choice = result.to_s.strip

      case choice
      when "Allow"
        handle_allow(domain)
        :allow
      when "Once Only"
        handle_allow_once(domain)
        :allow_once
      when "Deny"
        handle_deny(domain)
        :deny
      else
        Log.warn { "Unexpected rofi choice: #{choice}" }
        :deny
      end
    end

    private def self.handle_allow(domain : String) : Nil
      # Add to whitelist and allow
      config = Crybot::Config::Loader.load
      proxy_config = config.proxy
      whitelist = proxy_config.domain_whitelist.dup

      unless whitelist.includes?(domain)
        whitelist << domain
        Log.info { "Added #{domain} to whitelist" }

        # Update config with new whitelist
        updated_proxy = Crybot::Config::ProxyConfig.new(
          enabled: proxy_config.enabled,
          host: proxy_config.host,
          port: proxy_config.port,
          domain_whitelist: whitelist,
          log_file: proxy_config.log_file
        )

        # Update the full config
        updated_config = config
        updated_config.proxy = updated_proxy

        # Write updated config to file
        config_path = Crybot::Config::Loader.config_file
        File.write(config_path, updated_config.to_yaml)

        # Reload config
        Crybot::Config::Loader.reload
      end

      Log.info { "Allowed #{domain} - whitelisted now" }
    end

    private def self.handle_allow_once(domain : String) : Nil
      # Allow for this session only (no config change)
      Log.info { "Allowed #{domain} for this session only" }
    end

    private def self.handle_deny(domain : String) : Nil
      Log.warn { "Denied access to #{domain}" }
      # ameba:disable Documentation/DocumentationAdmonition
      # TODO: Notify proxy server if needed for config reload
    end
  end
end
