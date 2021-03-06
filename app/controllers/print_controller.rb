#Mapfish print controller with access control and servlet call

class PrintController < ApplicationController
  require 'popen4'
  begin
    require 'RMagick'
  rescue LoadError
    ActionController::Base.logger.info "Couldn't find RMagick. Image export not supported"
  end

  skip_before_filter :verify_authenticity_token, :only => :create # allow /print/create with POST

  caches_action :info

  class JavaError < Exception
    def initialize(cmd, message)
      super(cmd+"\n"+message)
    end
  end

  def initialize
    @configFile = "#{Rails.root}/config/print.yml"
  end

  TMP_PREFIX = "/opt/geodata/tmp/mfPrintTempFile" #WARNING: use NFS for multi-node setups! TODO: external config
  TMP_SUFFIX = ".pdf"
  TMP_PURGE_SECONDS = 600

  OUTPUT_FORMATS = ["pdf", "png", "jpg", "tif", "gif"]

  def info
    #if PRINT_URL.present?
    #TODO:  call_servlet(request)
    cmd = baseCmd + " --clientConfig"
    result = ""
    errors = ""
    status = POpen4::popen4(cmd) do |stdout, stderr, stdin, pid|

      result = stdout.readlines.join("\n")
      errors = stderr.readlines.join("\n")
    end
    if status.nil? || status.exitstatus != 0
      raise JavaError.new(cmd, errors)
    else
      info = ActiveSupport::JSON.decode(result)
      info['createURL'] = url_for(:protocol => request.protocol, :action=>'create') + '.json'
      # add output formats
      info['outputFormats'] = []
      OUTPUT_FORMATS.each do |output_format|
        info['outputFormats'] << {:name => output_format}
      end

      respond_to do |format|
        format.json do
          if params[:var]
            render :text=>"var "+params[:var]+"="+result+";"
          else
            render :json=>info
          end
        end
      end
    end
  end

  def create
    cleanupTempFiles

    accessible_topics = Topic.accessible_by(current_ability).collect{ |topic| topic.name }
    layers_to_delete = []
    request.parameters["layers"].each do |layer|
      if layer["baseURL"] # WMS layers
        topic = File.basename(URI.parse(layer["baseURL"]).path)
        if accessible_topics.include?(topic)
          # rewrite URL for local WMS, use CGI if layer filter is used
          use_cgi = !layer["customParams"].nil? && layer["customParams"].any? { |param, value| param =~ LAYER_FILTER_REGEX }
          layer["baseURL"] = rewrite_wms_uri(layer["baseURL"], use_cgi)
          if layer["customParams"] #Set map_resolution for mapserver (MapFish print bug?)
            layer["customParams"].delete("DPI")
            layer["customParams"]["map_resolution"] = request.parameters["dpi"]
          end
          # For permission check in WMS controller: pass session as WMS request parameter
          #layer["customParams"]["session"] =
        else
          # collect inaccessible layers for later removal
          layers_to_delete << layer
        end
      end

      if layer["baseURL"].nil? && layer["styles"] #Vector layers
        layer["styles"].each_value do |style| #NoMethodError (undefined method `each_value' for [""]:Array):
          if style["externalGraphic"]
            style["externalGraphic"].gsub!(LOCAL_GRAPHICS_HOST, '127.0.0.1')
            style["externalGraphic"].gsub!(/^https:/, 'http:')
          end
        end
      end
    end
    # remove inaccessible layers
    request.parameters["layers"] -= layers_to_delete

    request.parameters["pages"].each do |page|
      # round center coordinates
      page["center"].collect! {|coord| (coord * 100.0).round / 100.0  }
      # add blank user strings if missing
      page["user_title"] = " " if page["user_title"].blank?
      page["user_comment"] = " " if page["user_comment"].blank?
      # base url
      page["base_url"] = "#{request.protocol}#{request.host}"
      # disclaimer
      topic = Topic.accessible_by(current_ability).where(:name => page["topic"]).first
      page["disclaimer"] = topic.nil? ? Topic.default_print_disclaimer : topic.print_disclaimer
    end

    logger.info request.parameters.to_yaml

    if PRINT_URL.present?
      call_servlet(request)
    else
      #print-standalone
      tempId = SecureRandom.random_number(2**31)
      temp = TMP_PREFIX + tempId.to_s + TMP_SUFFIX
      cmd = baseCmd + " --output=" + temp
      result = ""
      errors = ""
      status = POpen4::popen4(cmd) do |stdout, stderr, stdin, pid|
        stdin.puts request.parameters.to_json
        #body = request.body
        #FileUtils.copy_stream(body, stdin)
        #body.close
        stdin.close
        result = stdout.readlines.join("\n")
        errors = stderr.readlines.join("\n")
      end
      if status.nil? || status.exitstatus != 0
        raise JavaError.new(cmd, errors)
      else
        convert_and_send_link(temp, tempId, request.parameters["dpi"], request.parameters["outputFormat"])
      end
    end
  end

  def show
    output_format = params[:format]
    if OUTPUT_FORMATS.include?(output_format)
      temp = TMP_PREFIX + params[:id] + ".#{output_format}"
      case output_format
      when "pdf"
        type = 'application/x-pdf'
      when "png"
        type = 'image/png'
      when "jpg"
        type = 'image/jpeg'
      when "tif"
        type = 'image/tiff'
      when "gif"
        type = 'image/gif'
      end
      send_file temp, :type => type, :disposition => 'attachment', :filename => params[:id] + ".#{output_format}"
    end
  end

  protected

  def rewrite_wms_uri(url, use_cgi)
    #http://wms.zh.ch/basis -> http://127.0.0.1/cgi-bin/mapserv.fcgi?MAP=/opt/geodata/mapserver/maps/intranet/basis.map&
    out = url
    # get topic from layer URL
    uri = URI.parse(url)
    localwms = LOCAL_WMS.any? { |ref| uri.host =~ ref }
    if localwms
      topic = File.basename(uri.path)
      localhost = (@zone == ZONE_INTRANET) ? '127.0.0.1' : 'localhost'
      out = "http://#{localhost}#{use_cgi ? MAPSERV_CGI_URL :  MAPSERV_URL}?MAP=#{MAPPATH}/#{@zone}/#{topic}.map&"
      #out = "http://#{localhost}:#{request.port}/wms/#{topic}"
    end
    out
  end

  def baseCmd
    "java -cp #{File.dirname(__FILE__)}/../../lib/print/print-standalone.jar org.mapfish.print.ShellMapPrinter --config=#{@configFile}"
  end

  def cleanupTempFiles
    minTime = Time.now - TMP_PURGE_SECONDS;
    OUTPUT_FORMATS.each do |output_format|
      Dir.glob(TMP_PREFIX + "*." + output_format).each do |path|
        if File.mtime(path) < minTime
          File.delete(path)
        end
      end
    end
  end

  def call_servlet(request)
    url = URI.parse(URI.decode(PRINT_URL))
    logger.info "Forward request: #{PRINT_URL}"
    printspec = request.parameters.to_json

    response = nil
    begin
      http = Net::HTTP.new(url.host, url.port)
      http.start do
        case request.method.to_s
        when 'GET'  then response = http.get(url.path) #, request.headers
        #when 'POST' then response = http.post(url.path, printspec)
        when 'POST'  then response = http.get("#{url.path}?spec=#{CGI.escape(printspec)}") #-> GET print.pdf
        else
          raise Exception.new("unsupported method `#{request.method}'.")
        end
      end
    rescue => err
      logger.info("#{err.class}: #{err.message}")
      render :nothing => true, :status => 500
      return
    end
    #send_data response.body, :status => response.code, :type=>'application/x-pdf', :disposition=>'attachment', :filename=>'map.pdf'
    tempId = SecureRandom.random_number(2**31)
    temp = TMP_PREFIX + tempId.to_s + TMP_SUFFIX
    File.open(temp, 'w') {|f| f.write(response.body) }
    convert_and_send_link(temp, tempId, request.parameters["dpi"], request.parameters["outputFormat"])
  end

  # optionally convert PDF to image and send link to print result
  def convert_and_send_link(temp_pdf, temp_id, dpi, output_format)
    temp_suffix = ".pdf"

    if output_format != "pdf" && OUTPUT_FORMATS.include?(output_format)
        # convert PDF to image
        pdf = Magick::Image.read(temp_pdf) { self.density = dpi }.first
        temp_suffix = ".#{output_format}"
        temp_img = TMP_PREFIX + temp_id.to_s + temp_suffix
        pdf.write(temp_img)
        File.delete(temp_pdf)
    end

    respond_to do |format|
      format.json do
        render :json=>{ 'getURL' => url_for(:action=>'show', :id=>temp_id) + temp_suffix }
      end
    end
  end

end
