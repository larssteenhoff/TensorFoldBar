#!/usr/bin/ruby
require 'net/http'
require 'json'

def positive_number(value, allow_zero: false)
  n = Float(value)
  n if n.finite? && (allow_zero ? n >= 0 : n > 0)
rescue ArgumentError, TypeError
  nil
end

def benchmark_rows(data, seconds)
  usage = data.fetch('usage')
  tokens = Integer(usage.fetch('completion_tokens'))
  raise 'Server returned no output tokens' unless tokens > 0 && seconds > 0
  runtime = data['tensorfold'] || {}
  prefill = positive_number(runtime['prefill_seconds'])
  ttft = positive_number(runtime['time_to_first_token'], allow_zero: true)
  prompt = positive_number(usage['prompt_tokens'], allow_zero: true)
  cached = positive_number((usage['prompt_tokens_details'] || {})['cached_tokens'], allow_zero: true)
  prefill_row = 'Prefill: unavailable'
  if prefill && prompt && cached && cached <= prompt
    computed = prompt - cached
    prefill_row = if computed > 0
      format('Prefill: %.1f tok/s', computed / prefill)
    else
      'Prefill: prompt fully cached'
    end
  end
  [
    format('Benchmark: %.1f tok/s overall · %.2f s', tokens / seconds, seconds),
    prefill_row,
    ttft ? format('Time to first token: %.1f ms', ttft * 1000) : 'Time to first token: unavailable'
  ]
end

# A single local request; includes prompt processing and generation time.
# No results or machine information are uploaded.
if __FILE__ == $PROGRAM_NAME
begin
  destination = ARGV.fetch(0)
  token_limit = Integer(ARGV.fetch(1, '64'))
  raise 'Output tokens must be between 1 and 4096' unless (1..4096).cover?(token_limit)
  uri = URI('http://127.0.0.1:8080/v1/chat/completions')
  http = Net::HTTP.new(uri.host, uri.port, nil)
  http.open_timeout = 5
  http.read_timeout = 600
  request = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
  request.body = JSON.generate(
    model: 'local-model', stream: false, max_tokens: token_limit, temperature: 0,
    messages: [{role: 'user', content: 'Explain how a rainbow forms. Write a detailed paragraph.'}]
  )
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = http.request(request)
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  raise "HTTP #{response.code}: #{response.body[0, 600]}" unless response.is_a?(Net::HTTPSuccess)
  data = JSON.parse(response.body)
  summary = benchmark_rows(data, seconds).join("\n")
  File.write(destination + '.tmp', summary)
  File.rename(destination + '.tmp', destination)
  puts "#{summary} (end-to-end; prompt time included)"
rescue StandardError => e
  warn "Benchmark failed: #{e.message}"
  exit 1
end
end
