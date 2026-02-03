require "kemal"
require "../agent/loop"
require "../session/manager"
require "./handlers/*"
require "./websocket/*"
require "./middleware/*"
require "./assets"
require "baked_file_handler"

module Crybot
  module Web
    class Server
      getter config, agent, sessions

      def initialize(@config : Config::ConfigFile)
        @agent = Agent::Loop.new(@config)
        @sessions = Session::Manager.instance
      end

      def start : Nil
        # Setup Kemal configuration
        Kemal.config.port = @config.web.port
        Kemal.config.host_binding = @config.web.host

        # Setup middleware
        setup_middleware

        # Setup routes
        setup_routes

        # Start Kemal
        Kemal.run
      end

      private def setup_middleware : Nil
        # Add CORS headers if enabled
        if @config.web.enable_cors?
          add_handler Crybot::Web::CORSHandler.new(@config.web.allowed_origins)
        end

        # Add baked file handler for static assets (embedded in binary)
        add_handler BakedFileHandler::BakedFileHandler.new(Crybot::Web::BakedAssets)

        # Add authentication middleware (but allow public paths)
        add_handler Crybot::Web::Middleware::AuthMiddleware.new(@config)
      end

      private def setup_routes : Nil
        # WebSocket endpoint
        ws "/ws/chat" do |socket|
          handle_chat_websocket(socket)
        end

        # API: Health check
        get "/api/health" do |env|
          Handlers::APIHandler.health(env)
        end

        # API: Status
        get "/api/status" do |env|
          Handlers::APIHandler.status(env, @config, @agent, @sessions)
        end

        # API: Auth validation
        post "/api/auth/validate" do |env|
          Handlers::AuthHandler.validate(env, @config)
        end

        # API: Chat (REST endpoint as alternative to WebSocket)
        post "/api/chat" do |env|
          handler = Handlers::ChatHandler.new(@agent, @sessions)
          handler.handle_message(env)
        end

        # API: Sessions
        get "/api/sessions" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.list_sessions(env)
        end

        get "/api/sessions/:id" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.get_session(env)
        end

        delete "/api/sessions/:id" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.delete_session(env)
        end

        # API: Config
        get "/api/config" do |env|
          handler = Handlers::ConfigHandler.new(@config)
          handler.get_config(env)
        end

        put "/api/config" do |env|
          handler = Handlers::ConfigHandler.new(@config)
          handler.update_config(env)
        end
      end

      private def handle_chat_websocket(socket) : Nil
        chat_socket = ChatSocket.new(@agent, @sessions)

        # This runs when the WebSocket connection opens
        chat_socket.on_open(socket)

        socket.on_message do |message|
          chat_socket.on_message(socket, message)
        end

        socket.on_close do
          chat_socket.on_close(socket)
        end
      end
    end
  end
end
