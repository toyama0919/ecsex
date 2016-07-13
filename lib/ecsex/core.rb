require 'hashie'
require "logger"
require "pp"
require "json"

module Ecsex
  class Core

    def initialize
      @ecs = Aliyun::ECS.new
      @region = ENV['ALIYUN_REGION']
      @log = Logger.new(STDOUT)
    end

    def client
      @ecs
    end

    def regions
      Hashie::Mash.new(@ecs.describe_regions({})).Regions.Region
    end

    def images(parameters)
      options = parameters
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_images options).Images.Image
    end

    def instances(parameters)
      options = parameters
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_instances(options)).Instances.Instance
    end

    def instances_with_id(instance_id)
      options = {}
      options[:instance_ids] = [instance_id]
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_instances(options)).Instances.Instance
    end

    def snapshots(parameters)
      options = parameters
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_snapshots(options)).Snapshots.Snapshot
    end

    def disks(parameters)
      options = parameters
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_disks(options)).Disks.Disk
    end

    def eip_addresses(parameters)
      options = parameters
      options[:region_id] = @region
      Hashie::Mash.new(@ecs.describe_eip_addresses(options)).EipAddresses.EipAddress
    end

    def copy_image(parameters)
      options = parameters
      options[:region_id] = @region
      @ecs.copy_image(options)
    end

    def create_image_with_instance(instance)
      image_name = %Q{#{instance.InstanceName}.#{Time.now.strftime('%Y%m%d%H%M%S')}}
      description = {}
      description[:PrivateIpAddress] = instance.VpcAttributes.PrivateIpAddress.IpAddress.first
      description[:Description] = instance.Description
      description[:HostName] = instance.HostName
      description[:InstanceName] = instance.InstanceName
      description[:ZoneId] = instance.ZoneId
      description[:InstanceType] = instance.InstanceType

      parameters = {
        instance_id: instance.InstanceId,
        image_name: image_name,
        description: description.to_json
      }
      create_image(parameters)
    end

    def create_image(parameters)
      options = parameters
      options[:region_id] = @region
      @ecs.create_image(options)
      @log.info(%Q{creating image => #{parameters[:image_name]}})
      loop do
        results = images({image_name: parameters[:image_name]})
        if !results.empty?
          @log.info(%Q{ImageId => #{results.first['ImageId']}})
          return results.first
        end
        sleep 10
      end
    end

    def delete_image(parameters)
      options = parameters
      options[:region_id] = @region
      @ecs.delete_image(options)
    end

    def delete_snapshot(parameters)
      options = parameters
      options[:region_id] = @region
      @ecs.delete_snapshot(options)
    end

    def delete_disk(parameters)
      @log.info(%Q{delete disk => #{parameters}})
      options = parameters
      options[:region_id] = @region
      @ecs.delete_disk(options)
    end

    def create_instance(parameters)
      options = parameters
      options[:region_id] = @region
      instance = @ecs.create_instance(options)
      loop do
        results = instances({instance_name: options[:instance_name]})
        if results.first.Status == 'Stopped'
          @log.info(%Q{created #{options[:instance_name]}})
          return instance
        end
        sleep 10
      end
    end

    def stop_and_delete_instance(instance_id:)
      wait_for_stop(instance_id: instance_id)
      options = { instance_id: instance_id }
      @ecs.delete_instance(options)
    end

    def delete_instance(parameters)
      @ecs.delete_instance(parameters)
      @log.info(%Q{deleted #{parameters}})
    end

    def delete_instance_with_name(name)
      instances(instance_name: name).each do |instance|
        parameters = { instance_id: instance.InstanceId }
        stop_instance(parameters)
        delete_instance(parameters)
      end
    end

    def delete_instance_with_id(instance_id)
      parameters = { instance_id: instance_id }
      stop_instance(parameters)
      delete_instance(parameters)
    end

    def stop_instance(parameters)
      wait_for_stop(parameters)
    end

    def allocate_eip_address
      options = {}
      options[:region_id] = @region
      @ecs.allocate_eip_address(options)
    end

    def release_eip_address(parameters)
      options = parameters
      options[:region_id] = @region
      @ecs.release_eip_address(options)
    end

    def associate_eip_address(parameters, define_allocation_id)
      allocation_id = if define_allocation_id
        define_allocation_id
      else
        eip_address = allocate_eip_address
        eip_address['AllocationId']
        @log.info(%Q{allocate #{eip_address}})
      end
      parameters[:allocation_id] = allocation_id
      parameters[:region_id] = @region
      @ecs.associate_eip_address(parameters)
    end

    def start_instance(parameters)
      parameters[:region_id] = @region
      @ecs.start_instance(parameters)
    end

    def wait_for_stop(parameters)
      results = instances_with_id(parameters[:instance_id])
      return if results.first.Status == 'Stopped'
      @ecs.stop_instance(parameters)
      loop do
        results = instances_with_id(parameters[:instance_id])
        if results.first.Status == 'Stopped'
          @log.info(%Q{stopped #{parameters[:instance_id]}})
          return
        end
        sleep 10
      end
    end
  end
end
