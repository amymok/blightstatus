require 'open-uri' 
require 'aws/s3'
require 'json'

module ImportHelpers
  
  @cache_directory = "#{Rails.root}" + '/tmp/cache/'
  
  # We are using S3 be sure to set Amazon authentication enviroment variables
  # > export AMAZON_ACCESS_KEY_ID='abcdefghijklmnop'
  # > export AMAZON_SECRET_ACCESS_KEY='1234567891012345'
  def connect_to_aws
    AWS::S3::Base.establish_connection!(
      :access_key_id     => ENV['AMAZON_ACCESS_KEY_ID'],
      :secret_access_key => ENV['AMAZON_SECRET_ACCESS_KEY']
    )
  end
  
  # take the s3 object and save the contents to local filesystem
  def download_from_aws(s3_obj)
    downloaded_file_path = @cache_directory + File.basename(s3_obj.path)
    
    p downloaded_file_path
    p local_file_digest = Digest::MD5.hexdigest(File.read(downloaded_file_path)) 
    p s3_file_digest = s3_obj.about[:etag][1..-2]

    # if( s3_file_digest != local_file_digest )
    if( false )
      p "Downloading new version"
      downloaded_file = File.new(downloaded_file_path, "wb")
      downloaded_file.write(s3_obj.value)
      downloaded_file.close   
    else
      p "Using cached version"
      # Rails.logger.info "Using cached version"
    end

    return downloaded_file_path
  end

  # download file and save the contents to local filesystem
  def download_json_convert_to_hash(url)
    open(url) do |json_string|      
      return ActiveSupport::JSON.decode(json_string).symbolize_keys
    end
  end


  # download file and save the contents to local filesystem
  def download_from_http(url)
    #return downloaded_file_path
  end

  # unzip files
  def unzip_file (file, destination)
    Zip::ZipFile.open(file) do |zip_file|
     zip_file.each do |file|
       file_path=File.join(destination, file.name)
       FileUtils.mkdir_p(File.dirname(file_path))
       zip_file.extract(file, file_path) unless File.exist?(file_path)
     end
   end
  end

  # unzip files
  def get_shapefile_from_remote_zipfile ( url )
    #zipfile = download_from_http( url )
  end


  def download_geojson_from_amazon (file_name, bucket_name)
    ImportHelpers.connect_to_aws
    s3obj = AWS::S3::S3Object.find(file_name, bucket_name)
    downloaded_file_path = ImportHelpers.download_from_aws(s3obj)
    downloaded_geojson = File.read(downloaded_file_path)
    JSON.parse(downloaded_geojson)
  end

end