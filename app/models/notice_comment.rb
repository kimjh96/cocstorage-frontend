class NoticeComment < ApplicationRecord
  belongs_to :notice
  belongs_to :user, optional: true

  has_many :notice_comment_replies

  validate :nickname_inspection, on: %i[create]
  validate :password_minimum_length, on: %i[create]

  before_destroy :destroy_notice_comment_replies

  def self.fetch_with_options(options = {})
    notice = Notice.find_by(id: options[:notice_id], is_draft: false, is_active: true)
    raise Errors::NotFound.new(code: 'COC006', message: "There's no such resource.") if notice.blank?

    notice_comments = notice.active_comments

    if options[:orderBy]
      notice_comments = notice_comments.order(created_at: :desc) if options[:orderBy] == 'latest'
      notice_comments = notice_comments.order(created_at: :asc) if options[:orderBy] == 'old'
    end

    notice_comments
  end

  def self.fetch_by_cached_with_options(options = {})
    notice = Notice.find_active_by_cached(id: options[:notice_id])

    redis_key = "notices-#{options[:notice_id]}-comments-#{options.values.to_s}"
    namespace = "notices-#{options[:notice_id]}-comments"

    notice_comments = Rails.cache.read(redis_key, namespace: namespace)
    pagination = Rails.cache.read("#{redis_key}/pagination", namespace: namespace)

    if notice_comments.blank? || pagination.blank?
      notice_comments = NoticeComment.where(notice_id: notice[:id])

      if options[:orderBy]
        notice_comments = notice_comments.order(created_at: :desc) if options[:orderBy] == 'latest'
        notice_comments = notice_comments.order(created_at: :asc) if options[:orderBy] == 'old'
      end

      notice_comments = notice_comments.page(options[:page]).per(options[:per] || 20)

      Rails.cache.write(redis_key, ActiveModelSerializers::SerializableResource.new(
        notice_comments,
        each_serializer: NoticeCommentSerializer
      ).as_json, namespace: namespace)
      Rails.cache.write("#{redis_key}/pagination", PaginationSerializer.new(notice_comments).as_json, namespace: namespace)

      notice_comments = Rails.cache.read(redis_key, namespace: namespace)
      pagination = Rails.cache.read("#{redis_key}/pagination", namespace: namespace)
    end

    {
      comments: notice_comments,
      pagination: pagination
    }
  end

  def self.find_with_options(options = {})
    options = options.merge(user_id: options[:user].id, is_member: true) if options[:user].present?
    options = options.merge(user_id: nil, is_member: false) if options[:user].blank?

    options = options.except(:user)

    notice_comment = find_by(options.except(:password))
    raise Errors::NotFound.new(code: 'COC006', message: "There's no such resource.") if notice_comment.blank?

    notice_comment
  end

  def self.create_with_options(options = {})
    options = options.merge(user_id: options[:user].id, is_member: true) if options[:user].present?
    options = options.merge(user_id: nil, is_member: false) if options[:user].blank?

    options = options.except(:user)

    options[:password] = BCrypt::Password.create(options[:password]) if options[:password].present?

    create!(options)
  end

  def self.destroy_for_member(options = {})
    notice_comment = find_with_options(options)
    notice_comment.destroy
  end

  def self.destroy_for_non_member(options = {})
    notice_comment = find_with_options(options)

    if BCrypt::Password.new(notice_comment.password) != options[:password].to_s
      raise Errors::BadRequest.new(code: 'COC027', message: 'Password do not match.')
    end

    notice_comment.destroy
  end

  def destroy_notice_comment_replies
    notice_comment_replies.destroy_all
  end

  private

  def nickname_inspection
    if !is_member && nickname.present?
      regex = /[ㄱ-ㅎㅏ-ㅣ가-힣a-zA-Z0-9]{2,10}/
      special_regex = "[ !@\#$%^&*(),.?\":{}|<>]"

      raise Errors::BadRequest.new(code: 'COC001', message: 'nickname is invalid') unless nickname =~ regex
      raise Errors::BadRequest.new(code: 'COC001', message: 'nickname is invalid') if nickname.length > 10
      raise Errors::BadRequest.new(code: 'COC001', message: 'nickname is invalid') if nickname.match(special_regex)
    end
  end

  def password_minimum_length
    if !is_member && password.present? && password.length < 7
      raise Errors::BadRequest.new(code: 'COC004', message: 'Password must be at least 7 characters long.')
    end
  end
end
