#!/usr/bin/ruby
require 'net/http'
require 'json'

# A single local request; includes prompt processing and generation time.
# No results or machine information are uploaded.
begin
  destination = ARGV.fetch(0)
  uri = URI('http://127.0.0.1:8080/v1/chat/completions')
  http = Net::HTTP.new(uri.host, uri.port, nil)
  http.open_timeout = 5
  http.read_timeout = 90
  request = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
  request.body = JSON.generate(
    model: 'local-model', stream: false, max_tokens: 64, temperature: 0,
    messages: [{role: 'user', content: 'Explain how a rainbow forms. Write a detailed paragraph.'}]
  )
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = http.request(request)
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  raise "HTTP #{response.code}: #{response.body[0, 600]}" unless response.is_a?(Net::HTTPSuccess)
  data = JSON.parse(response.body)
  tokens = Integer(data.fetch('usage').fetch('completion_tokens'))
  raise 'Server returned no output tokens' unless tokens > 0 && seconds > 0
  summary = format('Benchmark: %.1f tok/s · %.2f s · %d tokens', tokens / seconds, seconds, tokens)
  File.write(destination + '.tmp', summary)
  File.rename(destination + '.tmp', destination)
  puts "#{summary} (end-to-end; prompt time included)"
rescue StandardError => e
  warn "Benchmark failed: #{e.message}"
  exit 1
end
