require "./takarik/configuration"
require "./takarik/callbacks"
require "./takarik/mime_types"
require "./takarik/static_file_handler"
require "./takarik/session/store"
require "./takarik/session/memory_store"
require "./takarik/session/cookie_store"
require "./takarik/session/session"
require "./takarik/views/engine"
require "./takarik/base_controller"
require "./takarik/router"
require "./takarik/dispatcher"
require "./takarik/application"

require "./takarik/views/ecr_engine"
require "./takarik/views/ecr_renderer"

module Takarik
  VERSION = "0.1.0"
end
