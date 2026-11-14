require "rack/test"
require "rspec"
require "webmock/rspec"

ENV["RACK_ENV"] = "test"

require_relative "../app"

WebMock.disable_net_connect!

module SpecHelpers
  API_KEY = "test-key".freeze

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", name))
  end

  def context_with_key
    { "project_id" => 1, "configuration" => { "api_key" => API_KEY } }
  end

  def stub_products(query, body:, total: nil, status: 200)
    headers = { "Content-Type" => "text/xml" }
    headers["X-Tot-Nr-Of-Products"] = total.to_s if total
    stub_request(:get, "https://api.boekenbank.be/api/products")
      .with(query: hash_including(query.merge("key" => API_KEY)))
      .to_return(status: status, body: body, headers: headers)
  end

  def stub_search(query, body:, status: 200)
    stub_request(:get, "https://api.boekenbank.be/api/zoek")
      .with(query: hash_including(query.merge("key" => API_KEY)))
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def json_response
    JSON.parse(last_response.body)
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include SpecHelpers

  def app
    DokService
  end

  def call_tool(tool, params: {}, context: context_with_key)
    post "/call", { tool: tool, params: params, context: context }.to_json, { "CONTENT_TYPE" => "application/json" }
  end
end
