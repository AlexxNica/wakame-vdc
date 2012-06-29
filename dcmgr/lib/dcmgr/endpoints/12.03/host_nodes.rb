# -*- coding: utf-8 -*-

require 'dcmgr/endpoints/12.03/responses/host_node'

Dcmgr::Endpoints::V1203::CoreAPI.namespace('/host_nodes') do
  get do
    ds = M::HostNode.dataset

    ds = datetime_range_params_filter(:created, ds)

    if params[:node_id]
      ds = ds.filter(:node_id=>params[:node_id])
    end
    
    collection_respond_with(ds) do |paging_ds|
      R::HostNodeCollection.new(paging_ds).generate
    end
  end
  
  get '/:id' do
    # description 'Show status of the host'
    # param :account_id, :string, :optional
    hn = find_by_public_uuid(:HostNode, params[:id])
    raise E::UnknownHostNode, params[:id] if hn.nil?
    
    respond_with(R::HostNode.new(hn).generate)
  end
  
  post do
    # description 'Create a new host node'
    # param :id, :string, :required
    # param :arch, :string, :required
    # param :hypervisor, :string, :required
    # param :name, :string, :optional
    # param :offering_cpu_cores, :int, :required
    # param :offering_memory_size, :int, :required
    params.delete(:account_id) if params[:account_id]
    hn = M::HostNode.create(params)
    respond_with(R::HostNode.new(hn).generate)
  end

  delete '/:id' do
    # description 'Delete host node'
    # param :id, :string, :required
    hn = find_by_public_uuid(:HostNode, params[:id])
    raise E::UnknownHostNode, params[:id] if hn.nil?
    hn.destroy
    respond_with({:uuid=>hn.canonical_uuid})
  end

  put '/:id' do
    # description 'Update host node'
    # param :id, :string, :required
    # param :arch, :string, :optional
    # param :hypervisor, :string, :optional
    # param :name, :string, :optional
    # param :offering_cpu_cores, :int, :optional
    # param :offering_memory_size, :int, :optional
    hn = find_by_public_uuid(:HostNode, params[:id])
    raise E::UnknownHostNode, params[:id] if hn.nil?

    changed = {}
    (M::HostNode.columns - [:id]).each { |c|
      if params.has_key?(c.to_s)
        changed[c] = params[c]
      end
    }

    hn.update_fields(changed, changed.keys)
    respond_with(R::HostNode.new(hn).generate)
  end
end
