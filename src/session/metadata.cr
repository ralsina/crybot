require "json"
require "time"

module Crybot
  module Session
    struct Metadata
      include JSON::Serializable

      property title : String
      property description : String
      property last_message : String
      property updated_at : String
      property session_type : String

      def initialize(@title : String = "New Conversation",
                     @description : String = "",
                     @last_message : String = "",
                     @updated_at : String = Time.utc.to_rfc3339,
                     @session_type : String = "unknown")
      end

      def update_last_message(content : String) : Nil
        @last_message = content
        @updated_at = Time.utc.to_rfc3339
      end

      def update_description(new_description : String) : Nil
        @description = new_description
        @updated_at = Time.utc.to_rfc3339
      end

      def update_title(new_title : String) : Nil
        @title = new_title
        @updated_at = Time.utc.to_rfc3339
      end

      def updated_at_time : Time
        Time.parse_rfc3339(@updated_at)
      end
    end
  end
end
