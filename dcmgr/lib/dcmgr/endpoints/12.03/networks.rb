# -*- coding: utf-8 -*-

require 'dcmgr/endpoints/12.03/responses/network'

Dcmgr::Endpoints::V1203::CoreAPI.namespace '/networks' do
  get do
    # description "List networks in account"
    # params start, fixnum, optional
    # params limit, fixnum, optional
    ds = M::Network.dataset

    if params[:account_id]
      ds = ds.filter(:account_id=>params[:account_id])
    end

    ds = datetime_range_params_filter(:created, ds)
    ds = datetime_range_params_filter(:deleted, ds)

    if params[:service_type]
      validate_service_type(params[:service_type])
      ds = ds.filter(:service_type=>params[:service_type])
    end
    
    if params[:display_name]
      ds = ds.filter(:display_name=>params[:display_name])
    end
    
    collection_respond_with(ds) do |paging_ds|
      R::NetworkCollection.new(paging_ds).generate
    end
  end

  get '/:id' do
    # description "Retrieve details about a network"
    # params :id required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?

    respond_with(R::Network.new(nw).generate)
  end

  post do
    # description "Create new network"
    # params :gw required default gateway address of the network
    # params :network required network address of the network
    # params :prefix optional  netmask bit length. it will be
    #               set 24 if none.
    # params :description optional description for the network
    # params :display_name optional
    savedata = {
      :account_id=>@account.canonical_uuid,
      :ipv4_gw => params[:gw],
      :ipv4_network => params[:network],
      :prefix => params[:prefix].to_i,
      :network_mode => params[:network_mode],
    }
    if params[:service_type]
      validate_service_type(params[:service_type])
      savedata[:service_type] = params[:service_type]
    end
    if params[:display_name]
      savedata[:display_name] = params[:display_name]
    end
    savedata[:description] = params[:description] if params[:description]
    nw = M::Network.create(savedata)

    respond_with(R::Network.new(nw).generate)
  end

  delete '/:id' do
    # description "Remove network information"
    # params :id required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    nw.destroy

    respond_with([nw.canonical_uuid])
  end

  get '/:id/dhcp_ranges' do
    # description 'Register reserved IP address to the network'
    # params id, string, required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?

    respond_with(R::DhcpRangeCollection.new(nw.dhcp_range_dataset).generate)
  end
  
  put '/:id/dhcp_ranges' do
    # description 'Register reserved IP address to the network'
    # params id, string, required
    # params range_begin, string, required
    # params range_end, string, required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?

    nw.add_ipv4_dynamic_range(params[:range_begin], params[:range_end])
    respond_with({})
  end
  
  put '/:id/dhcp/reserve' do
    # description 'Register reserved IP address to the network'
    # params id, string, required
    # params ipaddr, [String,Array], required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?

    (params[:ipaddr].is_a?(Array) ? params[:ipaddr] : Array(params[:ipaddr])).each { |ip|
      nw.network_vif_ip_lease_dataset.add_reserved(ip)
    }
    respond_with({})
  end
  
  put '/:id/dhcp/release' do
    # description 'Unregister reserved IP address from the network'
    # params id, string, required
    # params ipaddr, [String,Array], required
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    
    (params[:ipaddr].is_a?(Array) ? params[:ipaddr] : Array(params[:ipaddr])).each { |ip|
      nw.network_vif_ip_lease_dataset.delete_reserved(ip)
    }
    respond_with({})
  end

  get '/:id/vifs' do
    # description 'List vifs on this network'
    # params start, fixnum, optional
    # params limit, fixnum, optional
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    ds = nw.network_vif_dataset
    
    collection_respond_with(ds) do |paging_ds|
      R::NetworkVifCollection.new(paging_ds).generate
    end
  end

  get '/:id/vifs/:vif_id' do
    # description "Retrieve details about a vif"
    # params id, string, required
    # params vif_id, string, required

    # Find a better way to convert to canonical network uuid.
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    vif = find_by_uuid(M::NetworkVif, params[:vif_id])
    raise E::UnknownNetworkVif, params[:vif_id] if vif.nil?
    
    # Compare nw.id and vif.network_id.

    respond_with(R::NetworkVif.new(vif).generate)
  end

  post '/:id/vifs' do
    # description "Create new network vif"
    # params id, string, required
    nw = find_by_uuid(M::Network, params[:id])

    savedata = {
      :network_id => nw.id
    }
    vif = M::NetworkVif.create(savedata)

    respond_with(R::NetworkVif.new(vif).generate)
  end

  delete '/:id/vifs/:vif_id' do
    # description 'Delete a vif on this network'
    # params id, string, required
    # params vif_id, string, required
    M::NetworkVif.lock!
    nw = find_by_uuid(M::Network, params[:id])

    vif = nw.network_vif.detect { |itr| itr.canonical_uuid == params[:vif_id] }
    raise(UnknownNetworkVif) if vif.nil?

    vif.destroy
    respond_with({})
  end

  put '/:id/vifs/:vif_id/attach' do
    # description 'Attach a vif to this vif'
    # params id, string, required
    # params vif_id, string, required
    M::NetworkVif.lock!
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    vif = find_by_uuid(M::NetworkVif, params[:vif_id])
    raise(E::NetworkVifNicNotFound, params[:vif_id]) if vif.nil?
    raise(E::NetworkVifAlreadyAttached) unless vif.network.nil?

    # Check that the vif belongs to network?

    instance = vif.instance
    vif.attach_to_network(nw)

    # Find better way of figuring out when an instance is not running.
    if instance.host_node
      on_after_commit do
        Dcmgr.messaging.submit("hva-handle.#{instance.host_node.node_id}", 'attach_nic',
                               nw.dc_network.name, vif.canonical_uuid)
      end
    end

    respond_with(R::NetworkVif.new(vif).generate)
  end

  put '/:id/vifs/:vif_id/detach' do
    # description 'Detach a vif to this vif'
    # params id, string, required
    # params vif_id, string, required
    M::NetworkVif.lock!
    nw = find_by_uuid(M::Network, params[:id])
    raise(E::UnknownNetwork, params[:id]) if nw.nil?
    vif = find_by_uuid(M::NetworkVif, params[:vif_id])
    raise(E::UnknownNetworkVif, params[:vif_id]) if vif.nil?
    # Verify the network id.
    raise(E::NetworkVifNotAttached) if vif.network_id.nil? or vif.network_id != nw.id

    instance = vif.instance
    vif.detach_from_network

    # Find better way of figuring out when an instance is not running.
    if instance.host_node
      on_after_commit do
        Dcmgr.messaging.submit("hva-handle.#{instance.host_node.node_id}", 'detach_nic',
                               nw.dc_network.name, vif.canonical_uuid)
      end
    end

    respond_with(R::NetworkVif.new(vif).generate)
  end

  get '/:id/services' do
    # description 'List services on this network'
    # params start, fixnum, optional
    # params limit, fixnum, optional
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork, params[:id] if nw.nil?
    ds = nw.network_service
    
    collection_respond_with(ds) do |paging_ds|
      R::NetworkServiceCollection.new(paging_ds).generate
    end
  end

  # # Make GRE tunnels, currently used for testing purposes.
  # post '/:id/tunnels' do
  #   # description 'Create a tunnel on this network'
  #   # params id required
  #   # params dest_id required
  #   # params dest_ip required
  #   # params tunnel_id required
  #   nw = find_by_uuid(M::Network, params[:id])

  #   tunnel_name = "gre-#{params[:dest_id]}-#{params[:tunnel_id]}"
  #   command = "/usr/share/axsh/wakame-vdc/ovs/bin/ovs-vsctl add-port br0 #{tunnel_name} -- set interface #{tunnel_name} type=gre options:remote_ip=#{params[:dest_ip]} options:key=#{params[:tunnel_id]}"

  #   system(command)
  #   respond_with({})
  # end

  # delete '/:id/tunnels/:tunnel_id' do
  #   # description 'Destroy a tunnel on this network'
  #   # params :id required
  #   # params :tunnel_id required
  #   nw = find_by_uuid(M::Network, params[:id])

  #   tunnel_name = "gre-#{params[:dest_id]}-#{params[:tunnel_id]}"

  #   system("/usr/share/axsh/wakame-vdc/ovs/bin/ovs-vsctl del-port br0 #{tunnel_name}")
  #   respond_with({})
  # end

  put '/:id' do
    # description
    # param :id, string, :required
    # param :display_name , string, :optional
    raise E::UndefinedNetworkID if params[:id].nil?
    nw = find_by_uuid(M::Network, params[:id])
    raise E::UnknownNetwork if nw.nil?
    
    nw.display_name = params[:display_name] if params[:display_name]
    nw.save_changes
    
    respond_with(R::Network.new(nw).generate)
  end
end
