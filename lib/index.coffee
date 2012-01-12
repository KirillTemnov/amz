#!/usr/bin/env coffee
#

opts             = require "./opts"
sys              = require "util"
aws              = require "aws-lib"
fs               = require "fs"
exports.version  = version = "0.1.2"


exports.USAGE    = USAGE = """
  amz - amazon EC2 instances deployer.

  amz [cmd] [options]

  Options:
    -v, --version : show amz version

  List of commands:

    start         : start new ec2 instance. Accept additional params:
      num                    - number of instances to run (default 1)
      --awsAccessKey key     - redefine access key
      --awsSecretKey secret  - redefine secret key
      --awsKeypairName name  - set keypair, instead of default (in config)
      --awsImageId id        - set amazon image id, instead of default (in config)
      --script name          - apply named script after starting mashinge(s)

    stop          : stop instance

    log, l        : show instances statistics

    help          : show this message

    history, h    : history of commands

    clear-history : reset all history commands

    add-script, as   : add new user script/ rewrite exiting script
      --name  script-name    - name of script to dump
      --path  path/to/script


    list-scripts, ls  : show list of user scripts

    dump-script, ds  : dump script to working directory
      --name script-name  - name of script to dump
      --to file           - filename to dump, default equals to script-name

    config, c     : set/unset config vars

"""

shortcuts = "0123456789abcdefghijklmnopqrstuvwxyz"
InstanceTypes = "m1.small|m1.large|m1.xlarge|c1.medium|c1.xlarge|m2.xlarge|m2.2xlarge|m2.4xlarge|t1.micro".split "|"

printInstansesFromReservationSet = (instances) ->
  rsItems = instances.reservationSet.item || []
  unless rsItems instanceof Array
    rsItems = [rsItems]

  found = no
  for it, j in rsItems
    found = yes
    i = it.instancesSet.item
    sc = shortcuts[j]? and "^#{shortcuts[j]}" or "  "
    out = "#{sc} #{i.instanceState.name} \t #{i.instanceId}\t#{i.instanceType} / #{i.architecture}\t(#{i.placement.availabilityZone})\t"
    if i.ipAddress
      out += "#{i.ipAddress} / #{i.dnsName}"
    console.log out

  unless found
    console.log "[No active machines running]"

###
Execute command

###
exports.execCmd = (cmd, args, source="") ->
  if args.v or args.version
    return console.log "version: #{version}"

  c = opts.config null                 # todo add path config option here
  unless cmd in ["help", "config", "c", "set", "del"]
    chk = c.checkOpts()
    if chk.length > 0
      return console.log "check error. missed options: #{chk.join ', '}"
    ec2 = aws.createEC2Client c.get("awsAccessKey"), c.get("awsSecretKey")

  switch cmd
    when "set"
      for k,v of args
        if k in ["_", "$0"]
          continue
        c.set k, v
      c.save()

    when "del"
      c.remove args._

    when "start"
      imgId          = args.imageId       || c.get "awsImageId"
      keyName        = args.keyName       || c.get "awsKeypairName"
      iType          = args.instanceType  || c.get "awsInstanceType"
      secGroup       = args.securityGroup || c.get "awsSecurityGroup"
      scriptContent  = c.scripts[args.script]? and c.scripts[args.script].data or null
      maxCount       = parseInt(args._[0])
      if isNaN maxCount
        maxCount = 1
      # todo read script from file
      unless iType in InstanceTypes
        return console.log "instance type must be one of #{InstanceTypes.join ', '}"

      amzOpts =
        ImageId           : imgId
        MaxCount          : maxCount
        MinCount          : 1
        KeyName           : keyName
        InstanceType      : iType
        "SecurityGroup.1" : secGroup


      if scriptContent
        amzOpts.UserData = new Buffer(scriptContent).toString "base64"

      ec2.call "RunInstances", amzOpts, (result) ->
        console.log "result = #{sys.inspect result, yes, 10}"
        c.addToHistory source

    when "stop"
      # try to stop last instance
      ec2.call "DescribeInstances", {}, (inst) ->
        rsItems = inst.reservationSet.item || []
        unless rsItems instanceof Array
          rsItems = [rsItems]

        runningIds = []
        for it, j in rsItems
          i = it.instancesSet.item
          if i.instanceState.name in ["running", "pending"]
            runningIds.push [i.instanceId, shortcuts[j]? and "^#{shortcuts[j]}" or "empty-value"]

        params = {}
        found = no

        if 0 is args._.length   # stop all instances
          for i, j in runningIds
            found = yes
            params["InstanceId.#{j+1}"] = i[0]
        else                    # search for instances
          j = 0
          args._.map (arg) ->
            for i in runningIds
              if arg in i
                params["InstanceId.#{j+1}"] = i[0]
                j++
                found = yes
        unless found
          console.log "all instances not active or terminated"
        else
          ec2.call "TerminateInstances", params, (result) ->
            console.log "instances shutting down..."
        c.addToHistory source

    when "log", "l"
      ec2.call "DescribeInstances", {}, printInstansesFromReservationSet
      c.addToHistory source
    when "help"
      console.log USAGE
    when "history", "h"
      hist = c.getHistory()
      if 0 is hist.length
        console.log "empty history"
      else
        console.log hist.join "\n"
    when "clear-history"
      c.resetHistory()
      console.log "history cleared"
    when "add-scr", "add-script", "as"
      c.addScript args.name, args.path
      c.addToHistory source
    when "list-scr", "list-scripts", "ls"
      found = no
      for k, v of c.scripts
        found = yes
        console.log "#{k}\t #{(v.data.length/1024).toFixed(2)}kB\t#{v.type || 'unknown'}\t[ #{new Date v.created} / #{new Date v.updated}]"
      unless found
        console.log "you don't have scripts, add one by:\namz add-scr --name=scriptName --path=scriptPath."
    when "remove-script", "rs"
      removed = no
      args._.map (sname) ->
        if c.scripts[sname]
          removed = yes
          delete c.scripts[sname]
      unless removed
        console.log "nothing to remove"
      else
        c.storeScriptSettings()

    when "dump-scr", "ds"
      if c.scripts[args.name]
        filename = args.to || args.name
        fs.writeFileSync filename, c.scripts[args.name].data
        console.log "dump to #{filename} finished"
      else
        console.log "script not found. use\namz ls\nto find scripts."
    when "config", "c"
      c.dump()
      c.addToHistory source
    else
      console.log USAGE



