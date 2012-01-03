#!/usr/bin/env coffee

argv  = require('optimist').argv
amz   = require "../lib/index"
amz.execCmd argv._.shift() || "help", argv, process.argv[2..].join ' '


