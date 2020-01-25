#!/usr/bin/env ruby
# encoding: utf-8

require 'singleton'
require 'yaml'
require 'pp'
require 'optparse'
require 'securerandom'
require 'openssl'
require 'digest/sha1'
require 'time'
require 'date'

puts clear = Digest::SHA2.digest("€ ∫∑x=1 ∆t π™").to_s
#puts key = Digest::MD5.digest "secret"