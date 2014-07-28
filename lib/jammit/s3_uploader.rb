require 'rubygems'
require 'hmac'
require 'hmac-sha1'
require 'net/https'
require 'base64'
require 'mimemagic'
require 'digest/md5'

module Jammit
  class S3Uploader
    include AWS::S3
    include Jammit::S3AssetsVersioning

    def initialize(options = { })
      @bucket = options[:bucket]
      unless @bucket
        @bucket_name = options[:bucket_name] || Jammit.configuration[:s3_bucket]
        @access_key_id = options[:access_key_id] || Jammit.configuration[:s3_access_key_id]
        @secret_access_key = options[:secret_access_key] || Jammit.configuration[:s3_secret_access_key]
        @bucket_location = options[:bucket_location] || Jammit.configuration[:s3_bucket_location]
        @cache_control = options[:cache_control] || Jammit.configuration[:s3_cache_control]
        @expires = options[:expires] || Jammit.configuration[:s3_expires]
        @acl = options[:acl] || Jammit.configuration[:s3_permission] || :public_read

        @bucket = find_or_create_bucket
        if use_invalidation?
          @changed_files = []
          @cloudfront_dist_id = options[:cloudfront_dist_id] || Jammit.configuration[:cloudfront_dist_id]
        end
      end
    end

    def upload
      log "Pushing assets to S3 bucket: #{@bucket.name}"
      log "Using invalidation method" if use_invalidation?
      log "Using versioned assets method with version #{assets_version}" if use_versioned_assets?
      globs = []

      # add default package path
      if Jammit.gzip_assets
        globs << "public/#{Jammit.package_path}/**/*.gz"
      else
        globs << "public/#{Jammit.package_path}/**/*.css"
        globs << "public/#{Jammit.package_path}/**/*.js"
      end

      # add images
      globs << "public/images/**/*" unless Jammit.configuration[:s3_upload_images] == false

      # add custom configuration if defined
      s3_upload_files = Jammit.configuration[:s3_upload_files]
      globs << s3_upload_files if s3_upload_files.is_a?(String)
      globs += s3_upload_files if s3_upload_files.is_a?(Array)

      # upload all the globs
      globs.each do |glob|
        upload_from_glob(glob)
      end

      invalidate_cache(@changed_files) if use_invalidation?
    end

    def upload_from_glob(glob)
      log "Processing files from #{glob}"
      Dir["#{ASSET_ROOT}/#{glob}"].each do |local_path|
        next if File.directory?(local_path)
        # note: remote path should be relative
        remote_path = local_path.gsub(/^#{ASSET_ROOT}\/public\//, "")

        use_gzip = false

        # handle gzipped files
        if File.extname(remote_path) == ".gz"
          use_gzip = true
          remote_path = remote_path.gsub(/\.gz$/, "")
        end

        if use_versioned_assets?  # upload ALL files with version prepended
          remote_path = versioned_path(remote_path, true)
        end

        # selectively upload files if local version is different
        # check if the file already exists on s3
        begin
          obj = @bucket[remote_path]
        rescue
          obj = nil
        end

        # if the object does not exist, or if the MD5 Hash / etag of the
        # file has changed, upload it
        if !obj || (obj.etag != Digest::MD5.hexdigest(File.read(local_path)))

          upload_file local_path, remote_path, use_gzip

          if use_invalidation? && obj
            log "File changed and will be invalidated in cloudfront: #{remote_path}"
            @changed_files << remote_path
          end
        else
          log "file has not changed: #{remote_path}"
        end
      end
    end

    def upload_file(local_path, remote_path, use_gzip)
      # save to s3
      log "#{local_path.gsub(/^#{ASSET_ROOT}\/public\//, "")} => #{remote_path}"
      new_object, options = @bucket.new_object, {}
      new_object.key = remote_path
      new_object.value = open(local_path).read
      options[:cache_control] = @cache_control if @cache_control
      options[:content_type] = MimeMagic.by_path(remote_path)
      options[:content_encoding] = "gzip" if use_gzip
      options[:expires] = @expires if @expires
      options[:access] = @acl if @acl
      new_object.store(options)
    end

    def find_or_create_bucket
      AWS::S3::Base.establish_connection!(:access_key_id => @access_key_id, :secret_access_key => @secret_access_key)

      # find or create the bucket
      begin
        Bucket.find(@bucket_name)
      rescue AWS::S3::NoSuchBucket
        log "Bucket not found. Creating '#{@bucket_name}'..."
        Bucket.create(@bucket_name, :access => @acl.to_sym)
        Bucket.find(@bucket_name)
      end
    end

    def invalidate_cache(files)
      return if files.empty?
      log "invalidating cloudfront cache for changed files: #{files.join(', ')}"
      paths = ""
      files.each do |key|
        paths += "<Path>/#{key}</Path>"
      end
      digest = HMAC::SHA1.new(@secret_access_key)
      digest << date = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S %Z")
      uri = URI.parse("https://cloudfront.amazonaws.com/2010-11-01/distribution/#{@cloudfront_dist_id}/invalidation")
      req = Net::HTTP::Post.new(uri.path)
      req.initialize_http_header({
        'x-amz-date' => date,
        'Content-Type' => 'text/xml',
        'Authorization' => "AWS %s:%s" % [@access_key_id, Base64.encode64(digest.digest).gsub("\n", '')]
      })
      req.body = "<InvalidationBatch>#{paths}<CallerReference>#{@cloudfront_dist_id}_#{Time.now.utc.to_i}</CallerReference></InvalidationBatch>"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.request(req)
      log result_message(req, res)
    end

    def result_message req, res
      if res.code == "201"
        'Invalidation request succeeded'
      else
        <<-EOM.gsub(/^\s*/, '')
        =============================
        Failed with #{res.code} error!
        Request path:#{req.path}
        Request header: #{req.to_hash}
        Request body:#{req.body}
        Response body: #{res.body}
        =============================
        EOM
      end
    end

    def log(msg)
      puts msg
    end

  end

end
