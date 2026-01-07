Code.require_file("lib/main.ex", __DIR__)

# Test the tokenizer
test_input = "'exe with \"quotes\"' /tmp/owl/f2"
IO.puts("Input: #{test_input}")
result = CLI.parse_arguments(test_input)
IO.inspect(result, label: "Tokens")
