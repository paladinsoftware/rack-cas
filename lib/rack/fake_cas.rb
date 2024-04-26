require 'rack'
require 'rack-cas/cas_request'

class Rack::FakeCAS

  @@cas_session = nil

  def self.mock_cas_session!(email: 'email@example.com')
    @@cas_session = { email: email }
  end

  def self.unmock_cas_session!
    @@cas_session = nil
  end

  def initialize(app, config={}, attributes_config={})
    @app = app
    @config = config || {}
    @attributes_config = attributes_config || {}
  end

  def call(env)
    @request = Rack::Request.new(env)
    cas_request = CASRequest.new(@request)

    if cas_request.path_matches? @config[:exclude_paths] || @config[:exclude_path]
      return @app.call(env)
    end

    case @request.path_info
    when '/login'
      # simulates CAS service (when no CAS session: login page, when CAS session present: redirect back to app)
      # can be also used as a built-in way to get to the login page without needing to return a 401 status
      if @@cas_session
        redirect_to @request.params['service'] + '?ticket=some-value'
      else
        if @request.xhr?
          render_status 401
        else
          render_login_page
        end
      end

    when '/logged_in'
      # simulates real CAS redirect back to app after establishing CAS session
      @@cas_session = {
        email: @request.params['email']
      }
      redirect_to @request.params['service']

    when '/logout'
      @@cas_session = nil
      @request.session.send respond_to?(:destroy) ? :destroy : :clear
      redirect_to "#{@request.script_name}/"

    else
      if @request.params['ticket'] # simulates ticket validation
        save_cas_data_to_session
        redirect_to @request.base_url + @request.path
      else
        response = @app.call(env)
        if response[0] == 401 # access denied - app did not found CAS session data
          redirect_to "#{@request.base_url}/login?service=#{@request.url}"
        else
          response
        end
      end
    end
  end

  protected

  def save_cas_data_to_session
    email = @@cas_session.fetch(:email)
    @request.session['cas'] = {}
    @request.session['cas']['user'] = 'fake-username'
    @request.session['cas']['extra_attributes'] = @attributes_config.fetch(email, {})
  end

  def render_login_page
    [ 200, { 'Content-Type' => 'text/html' }, [login_page] ]
  end

  def redirect_to(url)
    [ 302, { 'Content-Type' => 'text/plain', 'Location' => url }, ['Redirecting you...'] ]
  end

  def render_status(status)
    [ status, { 'Content-Type' => 'text/plain' }, [] ]
  end

  def login_page
    <<-EOS
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <title>Fake CAS</title>
  </head>
  <body>
    <form action="#{@request.script_name}/logged_in" method="post">
      <input type="hidden" name="service" value="#{@request.params['service']}"/>
      <label for="email">Email</label>
      <input id="email" name="email" type="text"/>
      <label for="password">Password</label>
      <input id="password" name="password" type="password"/>
      <input type="submit" value="Login"/>
    </form>
  </body>
</html>
    EOS
  end

end
