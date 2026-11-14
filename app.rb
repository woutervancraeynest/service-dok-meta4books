require "sinatra/base"
require "json"

require_relative "lib/tools/search_books"
require_relative "lib/tools/get_books"
require_relative "lib/tools/list_products"

class DokService < Sinatra::Base
  TOOLS = {
    "search_books" => Tools::SearchBooks,
    "get_book" => Tools::GetBook,
    "get_books" => Tools::GetBooks,
    "get_book_media" => Tools::GetBookMedia,
    "list_products" => Tools::ListProducts
  }.freeze

  set :show_exceptions, false
  set :host_authorization, { permitted_hosts: [] }

  get "/health" do
    "OK"
  end

  post "/call" do
    content_type :json
    data = JSON.parse(request.body.read)
    tool_name = data["tool"]
    handler = TOOLS[tool_name]

    return { error: "Unknown tool: #{tool_name}" }.to_json unless handler

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = handler.call(params: data.fetch("params", {}), context: data.fetch("context", {}))
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    $stdout.puts "[CALL] #{tool_name} project=#{data.dig('context', 'project_id')} #{elapsed}ms#{" error=#{result[:code]}" if result[:error]}" unless settings.test?
    result.to_json
  rescue JSON::ParserError => e
    status 400
    { error: "Invalid JSON: #{e.message}" }.to_json
  rescue StandardError => e
    $stderr.puts "[ERROR] #{tool_name}: #{e.class}: #{e.message}"
    $stderr.puts e.backtrace.first(5).join("\n")
    { error: "Internal error: #{e.class}" }.to_json
  end

  run! if app_file == $0
end
