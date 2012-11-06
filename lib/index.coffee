#!/usr/bin/env coffee
#

opts             = require "./opts"
sys              = require "util"
aws              = require "aws-lib"
fs               = require "fs"
exports.version  = version = "0.4.3"

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

    volumes                        : show volumes

    create-volume                  : create new volume
      --zone zoneName       - name of zone, required!
      --size Sz             - volume size in GB, default - 1
      --snapId snapsotId    - specify if required create volume from snapshot

    delete-volume                  : delete volume
      --id VolumeId         - id of volume for deleting, started from 'vol-...'

    attach-volume                  : attach volume to instance
      --instanceId id       - id of instance
      --volumeId            - id of volume
      --deviceId            - id of device

    detach-volume                  : detach volume from instance
      --volumeId            - id of volume

    delete-snapshot, rm-snap       : delete snapshot
      --snapId              - id of snapshot

    snapshot-volume, mk-snap       : snapshot volume
      --volumeId            - id of volume

    shapshots, snaps               : shpw snapshots

    describe-tags                  : describe all tags, used for debug

    config, c                      : list of config vars

    config set --confKey confValue : set config variable(s)

    config reset confKey           : remove config variable(s)

    --addToHistory                 : add commad to history

    --vc                           : use virtual config

"""

shortcuts = "0123456789abcdefghijklmnopqrstuvwxyz"
InstanceTypes = "m1.small|m1.large|m1.xlarge|c1.medium|c1.xlarge|m2.xlarge|m2.2xlarge|m2.4xlarge|t1.micro".split "|"

fetchTags = (fn) ->
  c = opts.config null                 # todo add path config option here
  ec2t = aws.createEC2Client c.get("awsAccessKey"), c.get("awsSecretKey"), {version: "2011-12-01"}
  ec2t.call "DescribeTags", {}, (result) ->
    itemTags = result?.tagSet?.item? and result.tagSet.item or []
    itemTags = itemTags instanceof Array and itemTags or [itemTags]
    tags = {}
    for it in itemTags
      tags[it.resourceId] || ={}
      tags[it.resourceId][it.key] = [it.value]
    fn tags

getInstancesFromReservationSet = (instances) ->
  rsItems = instances.reservationSet.item || []
  unless rsItems instanceof Array
    rsItems = [rsItems]
  rsItems

printInstansesFromReservationSet = (instances, config) ->
  rsItems = getInstancesFromReservationSet instances
  if config.get "json"
    console.log JSON.stringify rsItems, null, 2
  else
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

#
# Public: Execute command inline
#
exports.exec = (cmd, args) ->
  ec2 = aws.createEC2Client args.awsAccessKey, args.awsSecretKey, {version: "2011-12-01"}
  fn = args.fn or ->
  switch cmd
    when "log"
      ec2.call "DescribeInstances", {}, (instances) ->
        fn null, getInstancesFromReservationSet instances

    else
      fn msg: "unknown command"



###
Execute command
###
exports.execCmd = (cmd, args, source="") ->
  if args.v or args.version
    return console.log "version: #{version}"

  c = opts.config args                 # todo add path config option here
  unless cmd in ["help", "config", "c"]
    chk = c.checkOpts()
    if chk.length > 0
      return console.log "check error. missed options: #{chk.join ', '}"
    ec2 = aws.createEC2Client c.get("awsAccessKey"), c.get("awsSecretKey"), {version: "2011-12-01"}

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
      unless keyName
        return console.log "check error. missed option: awsKeypairName"

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
        if args.addToHistory
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
        if args.addToHistory
          c.addToHistory source

    when "log", "l"
      ec2.call "DescribeInstances", {}, (err, instances) ->
        if err
          return console.log "error showing instances"
        else
          printInstansesFromReservationSet instances, c
      if args.addToHistory
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
      if args.addToHistory
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
      if args.addToHistory
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

    when "volumes"
      if args.addToHistory    
        c.addToHistory source
#      fetchTags (tags) ->
      ec2.call "DescribeVolumes", {}, (result) ->
        if result?.volumeSet?.item?
          vInfo = []
          for v in result.volumeSet.item
            switch v.status
              when "in-use"
                st = "in-use".red
              when "available"
                st = "available".green
              else
                st = v.status.yellow
            s = "#{v.volumeId}\t\t#{v.size}Gb\t#{'string' is typeof v.snapshotId and v.snapshotId or '[no snapshot]'}\t#{v.availabilityZone}\t#{st}\t"
            if v.attachmentSet?.item?
              item = v.attachmentSet.item
              s += "[ -> #{item.instanceId}]".bold.green + "\t#{item.device}\t#{item.status}\t[ #{'true' is item.deleteOnTermination and 'temp' or 'permanant'} ]"
            if v.tagSet?.item?
              for ti in v.tagSet.item instanceof Array and v.tagSet.item or [v.tagSet.item]
                if ti.key is "Name"
                  s += "\n[ #{ti.value.blue} ]"
                  break
            vInfo.push s
          console.log "#{vInfo.join '\n'}"
        else
          console.log "error getting volumes!".bold
          console.log "#{JSON.stringify result, null, 2}"

    when "create-volume"
      unless args.zone
        return console.log "error, zone argument required"

      if args.addToHistory
        c.addToHistory source
      opts             = AvailabilityZone: args.zone || "us-east-1a" # or default zone
      opts.SnapshotId  = args.snapId if args.snapId
      opts.Size        = args.size || 1 unless opts.SnapshotId


      ec2.call "CreateVolume", opts, (result) ->
        if result?.Errors?.Error?.Message?
          console.log result.Errors.Error.Message
        else
          if args.name? and result.volumeId
            o2 = {"ResourceId.0": result.volumeId, "Tag.0.Key": "Name", "Tag.0.Value": args.name}
            ec2.call "CreateTags", o2, (reslt) ->
              if reslt?.Errors?.Error?.Message?
                console.log "error creating tag for volume (volume should still created)"
              else
                console.log "create new volume with id: #{result.volumeId}"
          else
            console.log "create new volume with id: #{result.volumeId}"


    when "delete-volume"
      unless args.id
        return console.log "error, id argument required"
      ids = args.id instanceof Array and args.id or [args.id]
      ids.map (id) ->
        ec2.call "DeleteVolume", {VolumeId: id}, (result) ->
          if result.return
            console.log "volume #{id} deleted"
          else
            console.log "#{JSON.stringify result, null, 2}"

    when "snapshots", "snaps"
      opts = {}
      if args.owner
        opts["Owner.0"] = args.owner
      if args.volumeId
        opts["Filter.0.Name"] = "volume-id"
        opts["Filter.0.Value.0"] = args.volumeId


      ec2.call "DescribeSnapshots", opts, (result) ->
        console.log "#{JSON.stringify result, null, 2}"

    when "delete-snapshot", "rm-snap"
      unless args.snapId
        return console.log "error, required option --snapId"
      snaps = args.snapId instanceof Array and args.snapId or [args.snapId]
      snaps.map (snap) ->
        ec2.call "DeleteSnapshot", {SnapshotId: snap}, (result) ->
          if result.return s "true"
            console.log "snap #{snap} deleted"
          else
            console.log "error deleting snap"
            #console.log "#{JSON.stringify result, null, 2}"

#    when "snap-progress"

    when "snapshot-volume", "mk-snap"
      unless args.volumeId
        return console.log "error, parameter volumeId missed"

      if args.addToHistory
        c.addToHistory source
      ec2.call "CreateSnapshot", {VolumeId: args.volumeId}, (result) ->
        if result?.Errors?.Error?.Message?
          console.log "error: #{result.Errors.Error.Message}"
        else
#progress
          ec2.call "DescribeSnapshots", {"Filter.0.Name": "volume-id", "Filter.0.Value.0": args.volumeId}, (result) ->
            console.log "snap = #{JSON.stringify result, null, 2}"

    when "attach-volume"
      unless args.instanceId and args.volumeId and args.deviceId
        return console.log "error, required options: --instanceId, --volumeId and --deviceId"
      volumes = args.volumeId instanceof Array and args.volumeId or [args.volumeId]
      devices = args.deviceId instanceof Array and args.deviceId or [args.deviceId]
      unless volumes.length is devices.length
        return console.log "volumes and devices must be same quantity"
      if args.addToHistory
        c.addToHistory source
      optsArray = []
      for i in [0...volumes.length]
        optsArray.push {VolumeId: volumes[i], InstanceId: args.instanceId, Device: devices[i]}
      optsArray.map (opts) ->
        ec2.call "AttachVolume", opts, (result) ->
          if result?.Errors?.Error?.Message?
            console.log "error attaching volume #{opts.Device}"
            console.log "#{JSON.stringify result}"
          else
            console.log "#{opts.Device} attached"

    when "detach-volume"
      unless args.volumeId
        return console.log "error, volumeId required"
      volumes = args.volumeId instanceof Array and args.volumeId or [args.volumeId]
      volumes.map (vol) ->
        ec2.call "DetachVolume", {VolumeId: vol}, (result) ->
          if result?.Errors?.Error?.Message?
            console.log "error attaching volume #{opts.Device}"
            console.log "#{JSON.stringify result}"
          else
            console.log "Volume #{vol} detached"


    when "describe-tags"
      ec2.call "DescribeTags", {}, (result) ->
        console.log "#{JSON.stringify result, null, 2}"

    when "regions", "r"
      if args.addToHistory
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
        if args.addToHistory
          c.addToHistory source
    else
      console.log USAGE



