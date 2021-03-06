require "thor"
require 'aliyun'

module Ecsex
  class CLI < Thor

    map '-v' => :version

    def initialize(args = [], options = {}, config = {})
      super(args, options, config)
      @global_options = config[:shell].base.options
      @core = Core.new
      @ecs = @core.client
    end

    desc 'regions', 'regions'
    def regions
      puts_json @core.regions
    end

    desc 'images', 'images'
    option :name, aliases: '-n', type: :string, required: false, desc: 'name'
    def images
      parameters = {
        image_name: options['name']
      }
      puts_json @core.images(parameters)
    end

    desc 'instances', 'instances'
    option :name, aliases: '-n', type: :string, desc: 'name'
    def instances
      parameters = {
        instance_name: options['name']
      }
      puts_json @core.instances(parameters)
    end

    desc 'snapshots', 'snapshots'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def snapshots
      parameters = {
        snapshot_name: options['name']
      }
      puts_json @core.snapshots(parameters)
    end

    desc 'eip_addresses', 'eip_addresses'
    option :eip_address, aliases: '-e', type: :string, desc: 'eip_address'
    def eip_addresses
      parameters = {}
      parameters[:eip_address] = options['eip_address'] if options['eip_address']
      puts_json @core.eip_addresses(parameters)
    end

    desc 'disks', 'disks'
    option :name, aliases: '-n', type: :string, desc: 'name'
    def disks
      parameters = {}
      parameters[:disk_name] = options['name'] if options['name']
      puts_json @core.disks(parameters)
    end

    desc 'release_eip_addresses', 'release_eip_addresses'
    option :eip_address, aliases: '-e', type: :string, desc: 'eip_address'
    def release_eip_addresses
      parameters = {}
      parameters[:eip_address] = options['eip_address'] if options['eip_address']
      @core.eip_addresses(parameters).each do |eip_addresse|
        @core.release_eip_address({ allocation_id: eip_addresse['AllocationId']})
      end
    end

    desc 'create_instance', 'create_instance'
    option :instance_type, type: :string, required: true, desc: 'instance_type'
    option :image_id, type: :string, required: true, desc: 'image_id'
    option :security_group_id, type: :string, required: true, desc: 'security_group_id'
    def create_instance
      parameters = {
        image_id: options['image_id'],
        instance_type: options['instance_type'],
        security_group_id: options['security_group_id']
      }
      @core.create_instance(parameters)
    end

    desc 'copy_image', 'copy_image'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    option :destination_region_id, type: :string, required: true, desc: 'destination_region_id'
    def copy_image
      @core.images(image_name: options['name']).each do |image|
        parameters = {
          image_id: image.ImageId,
          destination_image_name: image.ImageName,
          destination_description: image.Description,
          destination_region_id: options['destination_region_id']
        }
        @core.copy_image(parameters)
      end
    end

    desc 'create_image', 'create_image'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def create_image
      @core.instances(instance_name: options['name']).each do |instance|
        @core.create_image_with_instance(instance)
      end
    end

    desc 'copy', 'copy'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    option :params, aliases: '-p', type: :hash, default: {}, desc: 'params'
    option :renew, aliases: '-r', type: :boolean, default: false, desc: 'renew'
    def copy
      @core.instances(instance_name: options['name']).each do |instance|
        image = @core.create_image_with_instance(instance)
        if options['renew']
          @core.delete_instance_with_id(instance.InstanceId)
        end
        parameters = {
          image_id: image.ImageId,
          zone_id: instance.ZoneId,
          instance_name: instance.InstanceName,
          instance_type: instance.InstanceType,
          host_name: instance.HostName,
          v_switch_id: instance.VpcAttributes.VSwitchId,
          'system_disk.category': 'cloud_efficiency',
          security_group_id: instance.SecurityGroupIds.SecurityGroupId.first,
          description: instance.Description
        }
        parameters.merge!(options['params'].each_with_object({}){|(k,v),memo| memo[k.to_s.to_sym]=v})
        created_instance = @core.create_instance(parameters)
        @core.associate_eip_address({instance_id: created_instance['InstanceId']}, instance.EipAddress.AllocationId)
        @core.start_instance({instance_id: created_instance['InstanceId']})
      end
    end

    desc 'delete_image', 'delete_image'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def delete_image
      @core.images(image_name: options['name']).each do |image|
        parameters = {
          image_id: image.ImageId,
        }
        @core.delete_image(parameters)
      end
    end

    desc 'delete_snapshot', 'delete_snapshot'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def delete_snapshot
      @core.snapshots(snapshot_name: options['name']).each do |snapshot|
        parameters = {
          snapshot_id: snapshot.SnapshotId,
        }
        @core.delete_snapshot(parameters)
      end
    end

    desc 'delete_disk', 'delete_disk'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def delete_disk
      @core.disks(disk_name: options['name']).each do |disk|
        parameters = {
          disk_id: disk.DiskId,
        }
        @core.delete_disk(parameters)
      end
    end

    desc 'delete_instance', 'delete_instance'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def delete_instance
      @core.delete_instance_with_name(options['name'])
    end

    desc 'stop_instance', 'stop_instance'
    option :name, aliases: '-n', type: :string, required: true, desc: 'name'
    def stop_instance
      @core.instances(instance_name: options['name']).each do |instance|
        parameters = { instance_id: instance.InstanceId }
        puts @core.stop_instance(parameters)
      end
    end

    desc 'version', 'show version'
    def version
      puts VERSION
    end

    private

    def puts_json(data)
      puts JSON.pretty_generate(data)
    end
  end
end
