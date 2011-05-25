# Jammit S3

## Introduction

Jammit S3 is a jammit wrapper that provides appropriate hooks so you can easily deploy your assets to s3/cloudfront

It's especially great for Heroku user who use generated assets such as coffee-script and sass. jammit-s3 includes a script you can use as a hook to recompile and upload all your assets.


## Installation

To install jammit-s3, just use:

    gem install jammit-s3

If you are using Rails3, add it to your project's `Gemfile`:

    gem 'jammit-s3'


Jammit S3 already has a gem dependency for jammit, so I'd recommend removing any existing `gem 'jammit'` references from your Gemfile.


## Configuration

Within your `config/assets.yml`, just add a toplevel key called `s3_bucket` that contains the bucketname you want to use. If jammit-s3 doesn't find the bucket, it will try to create it. Bucketnames need to be globally unique. Learn more about bucketnames [here](http://support.rightscale.com/06-FAQs/FAQ_0094_-_What_are_valid_S3_bucket_names%3F)

    s3_bucket: my-awesome-jammit-bucket

## Deployment

To deploy your files to s3, just the jammit-s3 command at your project's root.

    jammit-s3

If using it in the context of your Rails3 app, I'd recommend using `bundle exec`

    bundle exec jammit-s3

## Saving Authentication Info

Set your authenticaton information within `config/assets.yml`

    s3_access_key_id: 03HDMNF59CWZ2J24T702
    s3_secret_access_key: 1TzRlDmuH8DoOlJ2tlwW8qx+i+Pfe0jzIouWI2BL

Replace these with your own access keys, found [here](https://aws-portal.amazon.com/gp/aws/developer/account/index.html?ie=UTF8&action=access-key).

As you probably don't want to check this data into source control, I'd recommend you just set it to an environment variable on your local box, and use ERB

    s3_access_key_id: <%= ENV['ACCESS_KEY_ID'] %>
    s3_secret_access_key: <%= ENV['SECRET_ACCESS_KEY'] %>

You can then set these env variables in your .bash_profile


## Folders to upload

By default, jammit-s3 will upload your configured asset directly, along with public/images. However you can customize this using the `s3_upload_files` setting, which should be a list of file globs.

    # adds image uploads
    s3_upload_files:
      - public/css/images/**

## Setting permissions on uploaded s3 objects

By default, jammit-s3 uses the permission setting found on the s3 bucket. However, you can override this with the config:

    s3_permission: public_read

Valid permission options are:

`private`: Owner gets FULL_CONTROL. No one else has any access rights. This is the default.

`public_read`: Owner gets FULL_CONTROL and the anonymous principal is granted READ access. If this policy is used on an object, it can be read from a browser with no authentication.

`public_read_write`: Owner gets FULL_CONTROL, the anonymous principal is granted READ and WRITE access. This is a useful policy to apply to a bucket, if you intend for any anonymous user to PUT objects into the bucket.

`authenticated_read`: - Owner gets FULL_CONTROL, and any principal authenticated as a registered Amazon S3 user is granted READ access.

## Using Amazon CloudFront (CDN)

For the following to work you need to make sure you have the CloudFront enabled
for your bucket via you Amazon acccount page. Go here: http://aws.amazon.com/cloudfront/ and click "Sign Up"

### CloudFront subtleties

CloudFront caching does not respect Rails cache busting
technique of appending a query string to each asset url. So when you
roll out a new build with that new amazing logo, CloudFront will treat
the url path /logo.png?123456 and /logo.png?56789 as the same file and
serve it from the cache without re-fetching it from the origin server.

To work around this issue jammit-s3 implements two strategies how to let CloudFront
know your files are updated: invalidation and asset versioning.

#### Invalidation

To configure jammit-s3 to use invalidation for CloudFront, simply add the following settings to config/assets.yml:

    use_cloudfront: invalidate
    cloudfront_dist_id: XXXXXXXXXXXXXX
    cloudfront_domain: xyzxyxyz.cloudfront.net
    cloudfront_cname: static.yourdomain.com # <- this is optional, and CF distribution needs to be configured for CNAMEs

Please note that cloudfront_dist_id is not the same as the CloudFront domain
name. Inside CloudFront management console select the
distribution, and you will see Distribution ID and Domain Name values.

There is nothing special to so at deployment time (except running jammit-s3 of course).

When configured for invalidation jammit-s3 will only upload the asset files if they are new or
different from the previous version in S3 bucket. For changed files jammit-s3 will issue
an invalidation request to Amazon.

#### Known issues with CloudFront invalidation

1. It may reportedly take up to 15 minutes to invalidate all the CloudFront
caches around the globe (and Amazon charges for more than a certain number
of invalidations per month).

2. It's non-atomic from the perspective of the end-user: They may get an
older version of the site with a newer version of the JavaScript and CSS, or
vice versa.

3. It doesn't play nicely with aggressive HTTP caching. For example, once you
serve a script or a stylesheet, you would like it to be cached indefinitely
with no more round trips to see whether it is valid.


#### Asset Versioning

To configure jammit-s3 to use asset versioning for CloudFront, simply add the following settings to config/assets.yml:

    use_cloudfront: version
    cloudfront_dist_id: XXXXXXXXXXXXXX  # <- optional, not used for versioning
    cloudfront_domain: xyzxyxyz.cloudfront.net

When configured for asset versioning, jammit-s3 inserts a cache busting token right
in the asset path, causing browsers and cacheing proxies to refetch it
from the origin server. The value of the cache busting token is read
from RAILS_ASSET_ID environment variable, and inserted right at the root
of the paths, e.g. =image_tag "logo.png" will generate an image tag with
href to http://xxxxx.cloudfront.net/a4f2c23/logo.png, where a4f2c23 is
the value of ENV['RAILS_ASSET_ID'] on your application server.

It is up to you to come up with a strategy which value to use as
RAILS_ASSET_ID, the git commit hash seems like a good option, but
anything relatively unique, like a timestamp will do.

#### Assets CNAME Distro ####

To configure asset versioning with a single CNAME, simple add the following setting to config/assets.yml:

    cloudfront_cname: static.yourdomain.com # <- this is optional, and CF distribution needs to be configured for CNAMEs

Although if you would like you use multiple CNAME's you can set the following in the config/assets.yml:

    cloudfront_cname:
      - static1.yourdomain.com
      - static2.yourdomain.com
      - static3.yourdomain.com

When configured this way, your assets are distributed, by source.hash number for all your assets spanning all of the CNAME's
provided.

#### Deployment

1. Run jammit-s3 with RAILS_ASSET_ID env var set
2. Set RAILS_ASSET_ID env var on your production environment

#### Run jammit-s3 with RAILS_ASSET_ID set

    $ RAILS_ASSET_ID=20110120051234 jammit-s3
    ...
    Rewriting /images/logo.png => /20110120051234/images/logo.png
    ...
    Uploading to s3: <path>/images/logo.png => 20110120051234/images/logo.png

jammit-s3 hooks into jammit's css compression routing to rewrite
absolute paths to images and other assets (fonts). Relative paths are
left alone as they will still work (advantage of prepending all paths
with the cache busting token).

After all compressed assets were generated, jammit-s3 uploads them to S3
bucket defined in config, under 20110120051234 directory. You may want
to clean up directory for older releases releases if you release quite
often.

#### Set RAILS_ASSET_ID in production environment

This totally depends on the enviroment and deployment tools you use.
For example on heroku.com run:

    $ heroku config:add RAILS_ASSET_ID=20110120051234

There is a convenience rake task the streamlines this provess:

    $ rake jammit:s3:heroku
    or
    $ rake jammit:s3:heroku[myapp]

This task will use last git commit as the value of RAILS_ASSET_ID, upload all assets to S3, and set heroku variable.

#### Pros and Cons for asset versioning

Pro: It assures that all files will match up, and the user will always get matched HTML/JS/CSS files.

Pro: Aggressive Cache-Control can be used

Con: Uploading of assets may take quite a bit of time and slow down your deployments.

Con: A bit more involved deployment

## Cache-Control setting

One advantage of versioning your assets through url is that they
effectively become immutable. You dont need to worry about browsers and
proxies serving stale versions, and can use very aggressive
Cache-Control setting. You can specify the value Amazon CloudFront will
use serving your assets by setting s3_cache_control config setting in
assets.yml:

   s3_cache_control: public, max-age=<%= 365 * 24 * 60 * 60 %>

This will cause Cache-Control response header to be set to 1 year
expiration.

## Bugs / Feature Requests

To suggest a feature or report a bug:
http://github.com/railsjedi/jammit-s3/issues/


## Jammit Home Page

Jammit S3 is a simple wrapper around Jammit. To view the original Jammit docs, use http://documentcloud.github.com/jammit/

