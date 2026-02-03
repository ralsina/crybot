require "tourmaline"
require "../agent/loop"
require "../config/loader"
require "../bus/events"

module Crybot
  module Channels
    class TelegramChannel
      @client : Tourmaline::Client
      @agent : Agent::Loop
      @allowed_users : Array(String)
      @offset_file : Path
      @processed_ids : Set(Int64) = Set(Int64).new
      @running : Bool = true

      def initialize(config : Config::ChannelsConfig::TelegramConfig, agent : Agent::Loop)
        puts "[#{Time.local.to_s("%H:%M:%S")}] Creating Tourmaline client (skipping get_me)..."

        # Create client with minimal pool size to speed up initialization
        # Tourmaline calls get_me during init which can be slow
        @client = Tourmaline::Client.new(config.token, pool_capacity: 10, initial_pool_size: 1)
        puts "[#{Time.local.to_s("%H:%M:%S")}] Tourmaline client created"

        @agent = agent
        @allowed_users = config.allow_from
        @offset_file = Config::Loader.sessions_dir / "telegram_offset.txt"

        # Load processed message IDs to avoid duplicates
        puts "[#{Time.local.to_s("%H:%M:%S")}] Loading processed IDs..."
        load_processed_ids

        # Register message handler
        puts "[#{Time.local.to_s("%H:%M:%S")}] Registering message handler..."
        @client.on(Tourmaline::UpdateAction::Message) do |ctx|
          handle_update(ctx)
        end
        puts "[#{Time.local.to_s("%H:%M:%S")}] Message handler registered"
      end

      def start : Nil
        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting polling (skipping webhook deletion)..."
        start_polling
      end

      def stop : Nil
        @running = false
      end

      private def start_polling : Nil
        puts "[#{Time.local.to_s("%H:%M:%S")}] Entering polling loop..."
        offset = 0_i64

        while @running
          begin
            updates = @client.get_updates(offset: offset, timeout: 30)
            updates.each do |update|
              @client.dispatcher.process(update)
              offset = update.update_id + 1
            end
          rescue e : Exception
            puts "[ERROR] Polling error: #{e.message}"
            sleep 1.second
          end
        end

        puts "[#{Time.local.to_s("%H:%M:%S")}] Polling stopped"
      end

      private def load_processed_ids : Nil
        ids_file = Config::Loader.sessions_dir / "telegram_processed_ids.txt"
        if File.exists?(ids_file)
          File.each_line(ids_file) do |line|
            @processed_ids.add(line.to_i64)
          end
          puts "[#{Time.local.to_s("%H:%M:%S")}] Loaded #{@processed_ids.size} processed message IDs from previous session"
        else
          puts "[#{Time.local.to_s("%H:%M:%S")}] No previous processed IDs found"
        end
      rescue e : Exception
        puts "[ERROR] Failed to load processed IDs: #{e.message}"
      end

      private def save_processed_id(update_id : Int64) : Nil
        @processed_ids.add(update_id)
        ids_file = Config::Loader.sessions_dir / "telegram_processed_ids.txt"
        File.open(ids_file, "a") do |file|
          file.puts(update_id)
        end
      rescue e : Exception
        # Ignore errors saving IDs
      end

      private def authorized?(user_id : Int64) : Bool
        return true if @allowed_users.empty?
        @allowed_users.includes?(user_id.to_s)
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def handle_update(ctx : Tourmaline::Context) : Nil
        start_time = Time.instant

        # Check if this update was already processed
        update_id = ctx.update.update_id
        if @processed_ids.includes?(update_id)
          return
        end

        # Mark as processed
        save_processed_id(update_id)

        # Check if user is authorized
        message = ctx.message
        return if message.nil?

        from_user = message.from
        return if from_user.nil?

        user_id = from_user.id
        return unless authorized?(user_id)

        # Get message content
        text = message.text || message.caption || ""
        return if text.empty?

        # Get chat info for logging
        chat_type = message.chat.type
        chat_title = message.chat.title || message.chat.first_name || "unknown"

        # Log incoming message
        puts "[#{Time.local.to_s("%H:%M:%S")}] Received from #{from_user.username || from_user.first_name || "user_#{user_id}"} (#{chat_type}: #{chat_title}): #{text}"

        # Create inbound message
        inbound = Bus::InboundMessage.new(
          channel: "telegram",
          sender_id: user_id.to_s,
          chat_id: message.chat.id.to_s,
          content: text,
          timestamp: Time.local,
        )

        # Process the message
        begin
          puts "[#{Time.local.to_s("%H:%M:%S")}] Processing..."
          process_start = Time.instant

          response = @agent.process(inbound.session_key, inbound.content)

          process_time = Time.instant - process_start
          puts "[#{Time.local.to_s("%H:%M:%S")}] Response ready (took #{process_time.total_seconds.to_i}s)"

          # Log response (truncated if too long)
          response_preview = response.size > 100 ? "#{response[0..100]}..." : response
          puts "[#{Time.local.to_s("%H:%M:%S")}] Response preview: #{response_preview}"
          puts "-" * 60

          # Send response back
          puts "[#{Time.local.to_s("%H:%M:%S")}] Sending to Telegram..."
          send_start = Time.instant

          send_response(ctx, response)

          send_time = Time.instant - send_start
          puts "[#{Time.local.to_s("%H:%M:%S")}] Sent! (took #{send_time.total_seconds.to_i}s)"

          total_time = Time.instant - start_time
          puts "[#{Time.local.to_s("%H:%M:%S")}] Total time: #{total_time.total_seconds.to_i}s"
        rescue e : Exception
          puts "[ERROR] #{e.message}"
          puts e.backtrace.join("\n") if ENV["DEBUG"]?
          ctx.respond("Error: #{e.message}")
        end
      end

      private def send_response(ctx : Tourmaline::Context, text : String) : Nil
        # Handle long messages by splitting them
        max_length = 4096
        if text.size <= max_length
          ctx.respond(text)
        else
          # Split message into chunks
          chunks = text.scan(/.{1,#{max_length}}/m).map { |match| match[0] }
          puts "[#{Time.local.to_s("%H:%M:%S")}] Sending response in #{chunks.size} chunk(s)"
          chunks.each_with_index do |chunk, index|
            chunk_start = Time.instant
            ctx.respond(chunk)
            chunk_time = Time.instant - chunk_start
            puts "[#{Time.local.to_s("%H:%M:%S")}] Chunk #{index + 1}/#{chunks.size} sent (took #{chunk_time.total_seconds.to_i}s)"
          end
        end
      end
    end
  end
end
