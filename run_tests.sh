#!/bin/bash

set -e

# Check that the "goblin town" non-DSL test approximately runs.
# TODO: convert this into a normal test format to run and check for exceptions.
ruby -I./lib exe/demirun test/proto_goblin_town_1.rb

RUBYOPT="-I./lib" ./exe/demirun test/proto_goblin_town_1.rb
