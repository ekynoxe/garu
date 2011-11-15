# GARU
#
# => A Ruby gem to place server side calls to google
# => analytics. Based on google analytics for mobile found
# => at http://code.google.com/mobile/analytics/
# => @Author: Mathieu Davy - ekynoxe http://ekynoxe.com
# => November 2011

require 'digest/md5'
require 'net/http'

class Garu
  attr_accessor :account, :request

  # Tracker version. (Kept from the google tools for mobile
  # => as it's using the same parameters)
  VERSION = "4.4sh"
  
  COOKIE_NAME = "__utmmobile"
  # The path the cookie will be available to, edit this to
  # => use a different cookie path.
  COOKIE_PATH = "/"
  # Two years in seconds.
  COOKIE_USER_PERSISTENCE = 63072000
  
  #Google URL called to record the tracker hit
  UTMGIFLOCATION = "http://www.google-analytics.com/__utm.gif"
  
  # 1x1 transparent GIF to be sent back in the response body
  GIF_DATA = [
      0x47.chr, 0x49.chr, 0x46.chr, 0x38.chr, 0x39.chr, 0x61.chr,
      0x01.chr, 0x00.chr, 0x01.chr, 0x00.chr, 0x80.chr, 0xff.chr,
      0x00.chr, 0xff.chr, 0xff.chr, 0xff.chr, 0x00.chr, 0x00.chr,
      0x00.chr, 0x2c.chr, 0x00.chr, 0x00.chr, 0x00.chr, 0x00.chr,
      0x01.chr, 0x00.chr, 0x01.chr, 0x00.chr, 0x00.chr, 0x02.chr,
      0x02.chr, 0x44.chr, 0x01.chr, 0x00.chr, 0x3b.chr
  ]
  
  def initialize (account, request)
    @request = request
    @account = account
  end
  
  # Get a random number string.
  def getRandomNumber
    return rand(0x7fffffff).to_s
  end
  
  # The last octect of the IP address is removed to
  # => anonymize the user.
  def getIP (remoteAddress=nil)
    if remoteAddress.nil?
      remoteAddress = @request.env['REMOTE_ADDR'].split(',').first
    end
    matches = /^([^.]+\.[^.]+\.[^.]+\.).*/.match(remoteAddress)
    if !matches[1].nil?
      remoteAddress = matches[1]+"0"
    else
      remoteAddress = ""
    end
    
    remoteAddress
  end
  
  # Generate a visitor id for this hit.
  # => If there is a visitor id in the cookie, use
  # => that, otherwise use the guid if we have one,
  # => otherwise use a random number.
  def getVisitorId(guid, account, userAgent, cookie)
    # If there is a value in the cookie, don't change it.
    if (!cookie.nil?)
      return cookie
    end
    
    message = ""
    
    if (!guid.nil?)
      # Create the visitor id using the guid.
      message = guid + account
    else
      # Otherwise this is a new user, create a new
      # => random id.
      message = userAgent + getRandomNumber
    end
    
    md5String = Digest::MD5.hexdigest(message)
    
    return "0x" + md5String[0..16]
  end
  
  # Make a tracking request to Google Analytics
  # => from this server.
  # => Copies the headers from the original
  # => request to the new one.
  def sendRequestToGoogleAnalytics(utmUrl)
    uri = URI.parse(utmUrl)
    req = Net::HTTP::Get.new(uri.request_uri)
    req['user_agent'] = @request.env["HTTP_USER_AGENT"]
    req['Accepts-Language:'] = @request.env["HTTP_ACCEPT_LANGUAGE"]
    
    res = Net::HTTP.start(uri.host, uri.port) {|http|
      http.request(req)
    }
    res
  end
  
  # Track a page view, updates all the cookies
  # => and campaign tracker, makes a server side
  # => request to Google Analytics and writes the
  # => transparent gif byte data to the response.
  def trackPageView()
    timeStamp = Time.now.getutc.to_i
    domainName = @request.host
    
    if domainName.nil?
      domainName = ""
    end
    
    # Get the referrer from the utmr parameter,
    # => this is the referrer to the page that
    # => contains the tracking pixel, not the
    # => referrer for tracking pixel.
    documentReferer = @request.env["HTTP_REFERER"]
    
    if (documentReferer.nil? && documentReferer != "0")
      documentReferer = "-"
    else
      documentReferer = URI.unescape(documentReferer)
    end
    
    documentPath = @request.path
    if documentPath.nil?
      documentPath = ""
    else
      documentPath = URI.unescape(documentPath)
    end
    
    account = @account
    userAgent = @request.env["HTTP_USER_AGENT"]
    if userAgent.nil?
      userAgent = ""
    end
    
    # Try and get visitor cookie from the request.
    cookie = @request.cookies[Garu::COOKIE_NAME]
    
    visitorId = getVisitorId(@request.env["HTTP_X_DCMGUID"], account, userAgent, cookie)
    
    # Construct the gif hit url.
    utmUrl = Garu::UTMGIFLOCATION + "?" +
        "utmwv=" + Garu::VERSION +
        "&utmn=" + getRandomNumber +
        "&utmhn=" + URI.escape(domainName) +
        "&utmr=" + URI.escape(documentReferer) +
        "&utmp=" + URI.escape(documentPath) +
        "&utmac=" + account.to_s +
        "&utmcc=__utma%3D999.999.999.999.999.1%3B" +
        "&utmvid=" + visitorId +
        "&utmip=" + getIP(@request.env["REMOTE_ADDR"])
    
    gaResponse = sendRequestToGoogleAnalytics(utmUrl)
    
    response = {
      'headers' => {
          'Content-Type'  => "image/gif",
          'Cache-Control' => "private, no-cache, no-cache=Set-Cookie, proxy-revalidate",
          'Pragma'        => "no-cache",
          'Expires'       => "Wed, 17 Sep 1975 21:32:10 GMT"
      },
      'body' => GIF_DATA.join
    }
    
    # If the debug parameter is on, add a header
    # => to the response that contains the url
    # => that was used to contact Google Analytics.
    if !@request.params["utmdebug"].nil?
      response["headers"].merge!({"X-GA-MOBILE-URL" => utmUrl})
    end
    
    # If no cookie was passed with the request,
    # => a new one has been created and therefore
    # => needs to be sent back in the response from Garu
    if !cookie
      response.merge!({'cookie' => {
        'name'     => COOKIE_NAME,
        'value'    => visitorId,
        'path'     => COOKIE_PATH,
        'domain'   => domainName,
        'expires'  => Time.at(timeStamp + COOKIE_USER_PERSISTENCE)
      }})
    end

    response
  end
end