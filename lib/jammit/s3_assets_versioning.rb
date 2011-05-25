require 'jammit/compressor'

module Jammit
  module S3AssetsVersioning

    # Need to only apply versioning when package_assets enabled and using
    # Amazon's CloudFront CDN service, since it does not honor
    # cache-busting query string to static assets.
    # One approach is to send invalidation request to Amazon CloudFront service (not implemented here).
    # Another approach is to embed the cache busting asset_version to the asset file name/path.
    # Rails calculates the cache busting token based on the file's File.mtime, but that is
    # resource expensive and may not be doable since the assets may only be hosted in CloudFront.
    # The most straight-forward solution is to use some release identifier and either insert
    # it in the file name or use it as the assets root for this release.
    # Currently S3AssetVersioning supports the separate assets root per release approach:
    # The final layout of the bucket when using CloudFront distribution:
    # <bucketname>/
    #   <assets_version1>/
    #     assets/...
    #     images/...
    #     javascripts/...
    #   <assets_verion2>/
    #     assets/...
    #     images/...
    #     javascripts/...

    # Returns true if need to apply filename/path versioning technique
    def use_versioned_assets?
      Jammit.package_assets && Jammit.configuration[:use_cloudfront]=="version"
    end

    def use_invalidation?
      Jammit.package_assets && Jammit.configuration[:use_cloudfront]=="invalidate"
    end

    # Separate asset host is used when Jammit-s3 gem is initialized and
    # package_assets is on for this environment (off for dev unless always is in the config)
    def use_s3_asset_host?
      Jammit.package_assets
    end

    # Returns a Proc that by default returns Amazon bucket, or, if configured,
    # the value of cloudfront_domain property from config/assets.yml.
    # Returned value is set directly to config.action_controller.asset_host.
    # For more complex needs set the value of config.action_controller.asset_host
    # to something else (like a Proc) inside config/environments/production.rb
    def asset_host_proc
      # http://docs.amazonwebservices.com/AmazonCloudFront/latest/DeveloperGuide/index.html?CNAMEs.html
      # CloudFront doesn't support CNAMEs with HTTPS, HTTPS needs to be served from cloudfront_domain.
      # If content is requested over HTTPS using CNAMEs, your end users' browsers will display the warning:
      # This page contains both secure and non-secure items. To prevent this message from appearing, don't use
      # CNAMEs with CloudFront HTTPS distributions.
      if Jammit.configuration[:use_cloudfront] && Jammit.configuration[:cloudfront_cname].present? && Jammit.configuration[:cloudfront_domain].present?
        asset_hostname = Jammit.configuration[:cloudfront_cname]
        asset_hostname_ssl = Jammit.configuration[:cloudfront_domain]
      elsif Jammit.configuration[:use_cloudfront] && Jammit.configuration[:cloudfront_domain].present?
        asset_hostname = asset_hostname_ssl = Jammit.configuration[:cloudfront_domain]
      else
        asset_hostname = asset_hostname_ssl = "#{Jammit.configuration[:s3_bucket]}.s3.amazonaws.com"
      end

      Proc.new do |source, request|
        if Jammit.configuration.has_key?(:ssl)
          protocol = Jammit.configuration[:ssl] ? "https://" : "http://"
        else
          protocol = "https://"
        end

        if request.ssl?
          "#{protocol}#{asset_hostname_ssl}"
        else
          if asset_hostname.is_a?(Array)
            i = source.hash % asset_hostname.size
            "#{protocol}#{asset_hostname[i]}"
          else
            "#{protocol}#{asset_hostname}"
          end
        end
      end
    end

    def asset_path_proc
      Proc.new do |source|
        versioned_path(source)
      end
    end

    # Called from a proc attached to config.action_controller.asset_path,
    # from monkey-patched Jammit::Compressor and from S3Uploader
    # to calculate asset paths
    def versioned_path(path, version_relative_paths=false)
      return path unless self.use_versioned_assets?
      return path if path.empty? || (Pathname.new(path).relative? && !version_relative_paths)
      version = assets_version
      return path if version.nil? || version.empty?
      version = Pathname.new(path).relative? ? "#{version}/" : "/#{version}"
      "#{version}#{path}"
    end

    # Returns a token used to version assets
    # Use RAILS_ASSET_ID var (as already used by Rails) if defined
    # or return an empty string
    def assets_version
      ENV["RAILS_ASSET_ID"] || ''
    end

    # Force to use a specific token to version assets
    def assets_version=(value)
      ENV["RAILS_ASSET_ID"] = value
    end
  end
end

# reopen class Compressor from jammit
class Jammit::Compressor
  # lets not pollute Compressor's namespace with AssetTagHelper
  class Helper;
    class << self
      include Jammit::S3AssetsVersioning;
    end
  end

  # monkey patch path calculations done in Jammit::Compressor
  # This method is used to calculate path to images referenced in stylesheets with url(path).
  alias old_rewrite_asset_path rewrite_asset_path

  def rewrite_asset_path(path, file_path)
    if Helper.use_versioned_assets?
      versioned_path = Helper.versioned_path(path)
      # make sure devs see what's being changed
      puts "Rewriting #{path} as #{versioned_path}" unless path == versioned_path
      versioned_path
    else
      old_rewrite_asset_path(path, file_path)
    end
  end
end

