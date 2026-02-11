require "log"
require "../config/loader"
require "../features/coordinator"

module Crybot
  module Commands
    Log = ::Log.for("crybot.commands")

    class Start
      def self.execute : Nil
        config = Config::Loader.load
        config = Config::Loader.migrate_config(config)

        coordinator = Features::Coordinator.new(config)
        coordinator.start
      end
    end
  end
end
