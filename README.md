# SurroGate

[![Gem Version](https://badge.fury.io/rb/surro-gate.svg)](https://badge.fury.io/rb/surro-gate)
[![Build Status](https://travis-ci.org/skateman/surro-gate.svg?branch=master)](https://travis-ci.org/skateman/surro-gate)
[![Inline docs](http://inch-ci.org/github/skateman/surro-gate.svg?branch=master)](http://inch-ci.org/github/skateman/surro-gate)
[![Code Climate](https://codeclimate.com/github/skateman/surro-gate/badges/gpa.svg)](https://codeclimate.com/github/skateman/surro-gate)

SurroGate is a generic purrpose TCP-to-TCP proxy for Ruby implemented using epoll.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'surro-gate'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install surro-gate

## Usage

```ruby
require 'surro-gate'

proxy = SurroGate.new

# Create a pair of TCP socket connections
sock_1 = TCPSocket.new('localhost', 1111)
sock_2 = TCPSocket.new('localhost', 2222)

# Push the pair of sockets to the proxy
proxy.push(sock_1, sock_2)

loop do
  # Select with a 1 second timeout
  proxy.select(1000)

  # Do some hard work
  proxy.each_ready do |left, right|
    begin
      right.write_nonblock(left.read_nonblock(4096))
    rescue => ex
      # ...
      proxy.pop(left, right) # Remove the failed connection pair from the proxy
    end
  end
end

```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skateman/surro-gate.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
