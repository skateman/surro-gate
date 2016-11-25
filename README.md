# SurroGate

[![Gem Version](https://badge.fury.io/rb/surro-gate.svg)](https://badge.fury.io/rb/surro-gate)
[![Build Status](https://travis-ci.org/skateman/surro-gate.svg?branch=master)](https://travis-ci.org/skateman/surro-gate)
[![Dependency Status](https://gemnasium.com/skateman/surro-gate.svg)](https://gemnasium.com/skateman/surro-gate)
[![Inline docs](http://inch-ci.org/github/skateman/surro-gate.svg?branch=master)](http://inch-ci.org/github/skateman/surro-gate)
[![Code Climate](https://codeclimate.com/github/skateman/surro-gate/badges/gpa.svg)](https://codeclimate.com/github/skateman/surro-gate)
[![codecov](https://codecov.io/gh/skateman/surro-gate/branch/master/graph/badge.svg)](https://codecov.io/gh/skateman/surro-gate)

SurroGate is a general purpose TCP-to-TCP proxy implemented in Ruby.

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

# Create two TCP socket connections
left = TCPSocket.new('localhost', 3333)
right = TCPSocket.new('localhost', 2222)

# Push the sockets to the proxy
proxy.push(left, right)

# Wait for the communication to finish
proxy.wait

```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skateman/surro-gate.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

