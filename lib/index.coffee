#!/usr/bin/env coffee
#

opts             = require "./opts"
sys              = require "util"
aws              = require "aws-lib"
fs               = require "fs"
exports.version  = version = "0.3.0"

require "colors"

exports.USAGE    = USAGE = """
  amz - amazon EC2 instances deployer.

  amz [cmd] [options]

  Options:
    -v, --version                  : show amz version

  List of commands:

    start                          : start new ec2 instance. Accept additional params:
      num                    - number of instances to run (default 1)
      --imageId i-id         - image id, instead of default in config
      --instanceType  iType  - instance type, instead of default in config, one of
                                m1.small, m1.large, m1.xlarge, c1.medium, c1.xlarge,
                                m2.xlarge, m2.2xlarge, m2.4xlarge, t1.micro
      --securityGroup sgName - name of security group, instead of default in config
      --script scriptName    - apply named script after starting mashinge(s)
      --name   machineName   - create named machine
      --zone   zoneName      - availability zone,  us-east-1a, us-east-1b, us-east-1c ...

    stop                           : stop instance. No parameters - stop all regular instances
                                     if machineName(s) is set via --name, only named machines
                                     will be shutting down. Shortcuts ^0 - ^9,  ^a-^z also
                                     availabile
      --name  machineName    - stop all machines with custom name

    list-ip                        : show list of IP adresses

    bind-ip                        : bind ip to instance, `ip` and `iid` are required

      --ip  ipAddress        - reserved ip address
      --iid instanceId       - instance id

    log, l                         : show instances statistics

    help                           : show this message

    history, h                     : history of commands

    clear-history                  : reset all history commands

    add-script, as                 : add new user script/ rewrite exiting script
      --script script-name    - name of script to dump
      --path  path/to/script

    list-scripts, ls               : show list of user scripts

    dump-script, ds                : dump script to working directory
      --script script-name    - name of script to dump
      --to file               - filename to dump, default equals to script-name


    zones, z                       : show availability zones
      --region Region name    - name of region, multiple keys applied

    regions, r                     : show amazon regions

    config, c                      : list of config vars

    config set --confKey confValue : set config variable(s)

    config reset confKey           : remove config variable(s)

"""

shortcuts = "0123456789abcdefghijklmnopqrstuvwxyz"
InstanceTypes = "m1.small|m1.large|m1.xlarge|c1.medium|c1.xlarge|m2.xlarge|m2.2xlarge|m2.4xlarge|t1.micro".split "|"

printInstansesFromReservationSet = (instances, config) ->
  rsItems = instances.reservationSet.item || []
  unless rsItems instanceof Array
    rsItems = [rsItems]

  found = no
  for it, j in rsItems
    found        = yes
    itemsList    = it.instancesSet.item
    unless itemsList instanceof Array
      itemsList  = [itemsList]

    for i in itemsList
      sc       = shortcuts[j]? and "^#{shortcuts[j]}".bold.green or "  "
      iname    = config.getInstanceName i.instanceId
      out      = "#{sc} #{iname? and iname.magenta or '\t'}\t "
      restStr  = "#{i.instanceState.name} \t #{i.instanceId}\t#{i.instanceType} / #{i.architecture}\t(#{i.placement.availabilityZone})\t"
      if i.ipAddress
        restStr += "#{i.ipAddress} / #{i.dnsName}"

      if i.instanceState.name in ["shutting-down", "pending"]
        restStr = restStr.yellow
      else if i.instanceState.name is "terminated"
        restStr = restStr.grey


      console.log out + restStr

  unless found
    config.removeAllInstanses()
    console.log "[No active machines running]"

###
Execute command

###
exports.execCmd = (cmd, args, source="") ->
  if args.v or args.version
    return console.log "version: #{version}"

  c = opts.config null                 # todo add path config option here
  unless cmd in ["help", "config", "c"]
    chk = c.checkOpts()
    if chk.length > 0
      return console.log "check error. missed options: #{chk.join ', '}"
    ec2 = aws.createEC2Client c.get("awsAccessKey"), c.get("awsSecretKey")

  switch cmd
    when "start"
      imgId          = args.imageId       || c.get "awsImageId"
      keyName        = args.keypairName   || c.get "awsKeypairName"
      iType          = args.instanceType  || c.get "awsInstanceType"
      secGroup       = args.securityGroup || c.get "awsSecurityGroup"
      zone           = args.zone          || null
      scriptContent  = c.scripts[args.script]? and c.scripts[args.script].data or null
      maxCount       = parseInt(args._[0])
      name           = args.name || null
      if isNaN maxCount
        maxCount = 1

      unless iType in InstanceTypes
        return console.log "instance type must be one of #{InstanceTypes.join ', '}"

      amzOpts =
        ImageId           : imgId
        MaxCount          : maxCount
        MinCount          : 1
        KeyName           : keyName
        InstanceType      : iType
        "SecurityGroup.1" : secGroup

      if zone
        amzOpts["Placement.AvailabilityZone"] = zone

      if scriptContent && scriptContent.length > 16 * 1024
        return console.log "Script '[args.script]' more than 16kb, mashine wouldn't started!"
      if scriptContent
        amzOpts.UserData = new Buffer(scriptContent).toString "base64"

      ec2.call "RunInstances", amzOpts, (result) ->
        if name
          iid = result.instancesSet.item.instanceId
          c.addNamedInstance name, iid
        itemsList = result.instancesSet.item
        unless itemsList instanceof Array
          itemsList = [itemsList]
        console.log "#{itemsList.length} instance#{itemsList.length > 1 and 's' or ''} started".bold.green
        c.addToHistory source

    when "stop"
      ec2.call "DescribeInstances", {}, (inst) ->
        rsItems = inst.reservationSet.item || []
        unless rsItems instanceof Array
          rsItems = [rsItems]

        runningIds = []
        for it, j in rsItems
          itemsList = it.instancesSet.item
          unless itemsList instanceof Array
            itemsList = [itemsList]
          for i in itemsList
            if i.instanceState.name in ["running", "pending"]
              runningIds.push [i.instanceId, shortcuts[j]? and "^#{shortcuts[j]}" or "empty-value"]

        params = {}
        found = no

        if args.name
          name  = (args.name instanceof Array) and args.name or [args.name]
          j     = 0
          for i in runningIds
            if c.getInstanceName(i[0]) in name
              params["InstanceId.#{j+1}"] = i[0]
              found = yes
              j++

        else if 0 is args._.length   # stop all instances
          j = 0
          for i in runningIds
            unless c.getInstanceName i[0]
              found = yes
              params["InstanceId.#{j+1}"] = i[0]
            else
              j++

        else                    # search for instances
          j = 0
          args._.map (arg) ->
            for i in runningIds
              if arg in i
                params["InstanceId.#{j+1}"] = i[0]
                found = yes
                j++

        unless found
          console.log "all instances not active or terminated"
        else
          ec2.call "TerminateInstances", params, (result) ->
            console.log "instances shutting down..."
        c.addToHistory source

    when "log", "l"
      ec2.call "DescribeInstances", {}, (instances) ->
        printInstansesFromReservationSet instances, c
      c.addToHistory source

    when "help"
      console.log USAGE

    when "list-ip"
      ec2.call "DescribeAddresses", {}, (addresses) ->
        itemsList = addresses.addressesSet.item
        unless itemsList instanceof Array
          itemsList = [itemsList]
        for i in itemsList
          s = "#{i.publicIp}\t\t#{('string' is typeof i.instanceId) and i.instanceId or '[none]'}"
          unless "string" is typeof i.instanceId
            s = s.grey
          else
            s = s.green.bold
          console.log s

    when "bind-ip"
      ec2.call "AssociateAddress", {PublicIp: args.ip, InstanceId: args.iid}, (result) ->
        if result.return
          console.log "done".bold.green
        else
          console.log result.Errors.Error.Message.red


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
      c.addScript args.script, args.path
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
      if c.scripts[args.script]
        filename = args.to || args.script
        fs.writeFileSync filename, c.scripts[args.script].data
        console.log "dump to #{filename} finished"
      else
        console.log "script not found. use\namz ls\nto find scripts."
    when "zones", "z"
      c.addToHistory source
      opts = {}
      args.region ||= []
      regions  = (args.region instanceof Array) and args.region or [args.region]
      for r, i in regions
        opts["ZoneName.#{i}"] = r

      ec2.call "DescribeAvailabilityZones", opts, (result) ->
        if result?.availabilityZoneInfo?.item?
          zInfo = []
          for x in result.availabilityZoneInfo.item
            if x.zoneState is "available"
              zInfo.push "#{x.zoneName}\t\t#{x.regionName}".green
            else
              zInfo.push "#{x.zoneName}\t\t#{x.regionName}".grey
          console.log "ZoneName\t\t\tRegion name\n#{zInfo.join '\n'}"
        else
          console.log "can't get zones info!".bold
          console.log "result = #{JSON.stringify result, null, 2}"

    when "regions", "r"
      c.addToHistory source
      ec2.call "DescribeRegions", {}, (result) ->
        if result?.regionInfo?.item?
          regInfo = ("#{x.regionName.green.bold}\t\t#{x.regionEndpoint}" for x in result.regionInfo.item)
          console.log "Region\t\t\tEnd point\n#{regInfo.join '\n'}"
        else
          console.log "can't get regions info!".bold

    when "config", "c"
      aux_cmd = args._.shift()
      if aux_cmd is "set"
        for k,v of args
          if k in ["_", "$0"]
            continue
          c.set k, v
        c.save()
      else if aux_cmd is "reset"
        c.remove args._
      else
        c.dump()
        c.addToHistory source
    else
      console.log USAGE



