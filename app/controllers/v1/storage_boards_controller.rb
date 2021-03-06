class V1::StorageBoardsController < V1::BaseController
  skip_before_action :authenticate_v1_user!, only: %i[
    index show non_members_edit non_members_update non_members_destroy non_members_drafts
    view_count non_members_images non_members_recommend latest popular
  ]

  def index
    data = StorageBoard.fetch_by_cached_with_options(configure_index_params)

    render json: data
  end

  def show
    data = StorageBoard.find_active_by_cached(configure_show_params)

    render json: data
  end

  def edit
    render json: StorageBoard.find_with_options(configure_edit_params),
           each_serializer: StorageBoardSerializer
  end

  def non_members_edit
    render json: StorageBoard.find_for_non_member(configure_non_members_edit_params),
           each_serializer: StorageBoardSerializer
  end

  def update
    namespace = "storages-#{configure_update_params[:storage_id]}-boards"

    Rails.cache.clear(namespace: namespace)
    Rails.cache.clear(namespace: "#{namespace}-detail")
    render json: StorageBoard.update_for_member(configure_update_params),
           each_serializer: StorageBoardSerializer
  end

  def non_members_update
    namespace = "storages-#{configure_non_members_update_params[:storage_id]}-boards"

    Rails.cache.clear(namespace: namespace)
    Rails.cache.clear(namespace: "#{namespace}-detail")
    render json: StorageBoard.update_for_non_member(configure_non_members_update_params),
           each_serializer: StorageBoardSerializer
  end

  def destroy
    namespace = "storages-#{configure_destroy_params[:storage_id]}-boards"

    Rails.cache.clear(namespace: namespace)
    Rails.cache.clear(namespace: "#{namespace}-detail")
    render json: StorageBoard.destroy_for_member(configure_destroy_params),
           each_serializer: StorageBoardSerializer
  end

  def non_members_destroy
    namespace = "storages-#{configure_non_members_destroy_params[:storage_id]}-boards"

    Rails.cache.clear(namespace: namespace)
    Rails.cache.clear(namespace: "#{namespace}-detail")
    render json: StorageBoard.destroy_for_non_member(configure_non_members_destroy_params),
           each_serializer: StorageBoardSerializer
  end

  def drafts
    render json: StorageBoard.create_draft(configure_draft_params),
           each_serializer: StorageBoardSerializer
  end

  def non_members_drafts
    render json: StorageBoard.create_draft(configure_draft_params),
           each_serializer: StorageBoardSerializer
  end

  def view_count
    render json: StorageBoard.update_active_view_count(configure_view_count_params),
           each_serializer: StorageBoardSerializer
  end

  def images
    storage = StorageBoard.find_with_options(configure_images_params)
    storage.images.attach(params[:image])

    render json: {
      image_url: storage.last_image_url
    }
  end

  def non_members_images
    storage = StorageBoard.find_with_options(configure_images_params)
    storage.images.attach(params[:image])

    render json: {
      image_url: storage.last_image_url
    }
  end

  def recommend
    ApplicationRecord.transaction do
      redis_key = "storages-#{configure_recommend_params[:storage_id]}-boards-#{configure_recommend_params[:id]}"
      namespace = "storages-#{configure_recommend_params[:storage_id]}-boards-detail"

      Rails.cache.delete(redis_key, namespace: namespace)
      render json: StorageBoard.update_recommend_with_options(configure_recommend_params),
             each_serializer: StorageBoardSerializer
    end
  end

  def non_members_recommend
    ApplicationRecord.transaction do
      redis_key = "storages-#{configure_recommend_params[:storage_id]}-boards-#{non_members_configure_recommend_params[:id]}"
      namespace = "storages-#{non_members_configure_recommend_params[:storage_id]}-boards-detail"

      Rails.cache.delete(redis_key, namespace: namespace)
      render json: StorageBoard.update_recommend_with_options(non_members_configure_recommend_params),
             each_serializer: StorageBoardSerializer
    end
  end

  def latest
    redis_key = 'storages-boards-latest'
    namespace = 'storages-boards'

    data = Rails.cache.read(redis_key, namespace: namespace)

    if data.blank?
      data = StorageBoard.where(is_draft: false, is_active: true).limit(10).order(id: :desc)

      Rails.cache.write(redis_key, ActiveModelSerializers::SerializableResource.new(
        data,
        each_serializer: StorageBoardSerializer
      ).as_json, expires_in: 5.minutes, namespace: namespace)
      data = Rails.cache.read(redis_key, namespace: namespace)
    end

    render json: data
  end

  def popular
    redis_key = 'storages-boards-popular'
    namespace = 'storages-boards'

    data = Rails.cache.read(redis_key, namespace: namespace)

    if data.blank?
      data = StorageBoard.where(is_draft: false, is_active: true, is_popular: true).limit(10).order(id: :desc)

      Rails.cache.write(redis_key, ActiveModelSerializers::SerializableResource.new(
        data,
        each_serializer: StorageBoardSerializer
      ).as_json, expires_in: 5.minutes, namespace: namespace)
      data = Rails.cache.read(redis_key, namespace: namespace)
    end

    render json: data
  end

  private

  def index_attributes
    %w[storage_id subject content nickname orderBy per page]
  end

  def show_attributes
    %w[storage_id id]
  end

  def edit_attributes
    %w[storage_id id]
  end

  def non_members_edit_attributes
    %w[storage_id id password]
  end

  def update_attributes
    %w[storage_id id subject content description]
  end

  def non_members_update_attributes
    %w[storage_id id subject content nickname password description]
  end

  def destroy_attributes
    %w[storage_id id]
  end

  def non_members_destroy_attributes
    %w[storage_id id password]
  end

  def view_count_attributes
    %w[storage_id id]
  end

  def images_attributes
    %w[storage_id id]
  end

  def recommend_attributes
    %w[storage_id id type]
  end

  def non_members_recommend_attributes
    %w[storage_id id type]
  end

  def configure_index_params
    index_attributes.each do |key|
      if params.key? key.to_sym
        raise Errors::BadRequest.new(code: 'COC013', message: "#{key} is empty") if params[key.to_sym].blank?
      end
    end

    params.permit(index_attributes)
  end

  def configure_show_params
    params.permit(show_attributes)
  end

  def configure_edit_params
    params.permit(edit_attributes).merge(user: current_v1_user)
  end

  def configure_non_members_edit_params
    raise Errors::BadRequest.new(code: 'COC000', message: 'password is required') if params[:password].blank?

    params.permit(non_members_edit_attributes)
  end

  def configure_update_params
    if params.key? :subject
      raise Errors::BadRequest.new(code: 'COC013', message: 'subject is empty') if params[:subject].blank?
    end

    if params.key? :content
      raise Errors::BadRequest.new(code: 'COC013', message: 'content is empty') if params[:content].blank?
    end

    params.permit(update_attributes).merge(user: current_v1_user)
  end

  def configure_non_members_update_params
    non_members_update_attributes.each do |key|
      if key == 'nickname'
        raise Errors::BadRequest.new(code: 'COC000', message: "#{key} is required") if params[key].blank?
      end

      if key == 'password'
        raise Errors::BadRequest.new(code: 'COC000', message: "#{key} is required") if params[key].blank?
      end
    end

    if params.key? :subject
      raise Errors::BadRequest.new(code: 'COC013', message: 'subject is empty') if params[:subject].blank?
    end

    if params.key? :content
      raise Errors::BadRequest.new(code: 'COC013', message: 'content is empty') if params[:content].blank?
    end

    params.permit(non_members_update_attributes)
  end

  def configure_destroy_params
    params.permit(destroy_attributes).merge(user: current_v1_user)
  end

  def configure_non_members_destroy_params
    raise Errors::BadRequest.new(code: 'COC000', message: 'password is required') if params[:password].blank?

    params.permit(non_members_destroy_attributes)
  end

  def configure_view_count_params
    params.permit(view_count_attributes)
  end

  def configure_draft_params
    {
      storage_id: params[:storage_id],
      user: current_v1_user,
      created_ip: request.headers['CF-Connecting-IP'] || request.remote_ip,
      created_user_agent: request.user_agent
    }
  end

  def configure_images_params
    raise Errors::BadRequest.new(code: 'COC000', message: 'image is required') if params[:image].blank?

    if params.key? :image
      unless params[:image].is_a? ActionDispatch::Http::UploadedFile
        raise Errors::BadRequest.new(code: 'COC014', message: 'image is not a file')
      end

      unless params[:image].content_type.in?(%w[image/png image/gif image/jpg image/jpeg])
        raise Errors::BadRequest.new(code: 'COC016', message: "#{params[:image].content_type} is unacceptable image format")
      end
    end

    params.permit(images_attributes).merge(user: current_v1_user)
  end

  def configure_recommend_params
    raise Errors::BadRequest.new(code: 'COC000', message: 'type is required') if params[:type].blank?

    params.permit(recommend_attributes).merge(user: current_v1_user, request: request)
  end

  def non_members_configure_recommend_params
    params.permit(non_members_recommend_attributes).merge(request: request)
  end
end
