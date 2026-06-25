require 'spec_helper'

describe Rack::CAS do
  let(:server_url) { 'http://example.com/cas' }
  let(:app_options) { {'fake' => false} }
  let(:ticket) { 'ST-0123456789ABCDEFGHIJKLMNOPQRS' }

  def app
    cas_test_app app_options
  end

  describe 'public request' do
    subject { get '/public' }
    its(:status) { should eql 200 }
  end

  describe 'ticket validation request' do
    subject { get '/private?search=blah&ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }
    its(:status) { should eql 302 }
    its(:location) { should eql 'http://example.org/private?search=blah' }

    context 'without additional query parameters' do
      subject { get '/private?ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }
      its(:status) { should eql 302 }
      its(:location) { should eql 'http://example.org/private' }
    end

    context 'with extra_attributes_filter set' do
      let(:app_options) { { extra_attributes_filter: [:cn, :mail] } }

      before { get '/private?ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }
      subject { last_request.session['cas']['extra_attributes'] }
      it { should have_key 'cn' }
      it { should have_key 'mail' }
      it { should_not have_key 'title' }
    end

    context 'with company_uuid in extra_attributes' do
      before { get '/private?ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }

      it 'should store company_uuid in session extra_attributes' do
        expect(last_request.session['cas']['extra_attributes']).to have_key 'company_uuid'
      end

      it 'should store company_uuid separately in session' do
        expect(last_request.session['company_uuid']).to eql '550e8400-e29b-41d4-a716-446655440000'
      end
    end

    context 'with extra_attributes_filter excluding company_uuid' do
      let(:app_options) { { extra_attributes_filter: [:cn, :mail] } }

      before { get '/private?ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }

      it 'should not include company_uuid in filtered extra_attributes' do
        expect(last_request.session['cas']['extra_attributes']).not_to have_key 'company_uuid'
      end

      it 'should not store company_uuid in session when filtered out' do
        expect(last_request.session['company_uuid']).to be_nil
      end
    end

    context 'with extra_attributes_filter including company_uuid' do
      let(:app_options) { { extra_attributes_filter: [:cn, :mail, :company_uuid] } }

      before { get '/private?ticket=ST-0123456789ABCDEFGHIJKLMNOPQRS' }

      it 'should include company_uuid in filtered extra_attributes' do
        expect(last_request.session['cas']['extra_attributes']).to have_key 'company_uuid'
      end

      it 'should store company_uuid in session' do
        expect(last_request.session['company_uuid']).to eql '550e8400-e29b-41d4-a716-446655440000'
      end
    end

    context 'with an invalid ticket' do
      before { RackCAS::ServiceValidationResponse.any_instance.stub(:user) { raise RackCAS::ServiceValidationResponse::TicketInvalidError } }
      its(:status) { should eql 302 }
      its(:location) { should eql 'http://example.com/cas/login?service=http%3A%2F%2Fexample.org%2Fprivate%3Fsearch%3Dblah' }
    end
  end

  describe 'logout request' do
    context 'without params' do
      subject { get '/logout' }
      its(:status) { should eql 302 }
      its(:location) { should eql 'http://example.com/cas/logout' }
    end

    context 'with params' do
      subject { get '/logout', gateway: 'true', service: 'http://example.com' }
      its(:status) { should eql 302 }
      its(:location) { should eql 'http://example.com/cas/logout?gateway=true&service=http%3A%2F%2Fexample.com' }
    end
  end

  describe 'single sign out request' do
    let(:app_options) {
      session_store = double('session_store')
      session_store.stub(:destroy_session_by_cas_ticket).and_return 1
      session_store.should_receive(:destroy_session_by_cas_ticket).with(ticket)

      { session_store: session_store }
    }

    subject { post "/?logoutRequest=#{URI::DEFAULT_PARSER.escape(fixture('single_sign_out_request.xml'))}" }
    its(:status) { should eql 200 }
    its(:body) { should eql 'CAS Single-Sign-Out request intercepted.' }
  end

  describe 'excluded request by path' do
    let(:app_options) { { exclude_path: '/private', session_store: nil } }

    subject { get '/private' }
    its(:status) { should eql 401 }
    its(:body) { should eql 'Authorization Required' }
  end

  describe 'excluded request by request validator' do
    let(:app_options) {
      { exclude_request_validator: Proc.new { |req| req.env['HTTP_CONTENT_TYPE'] == 'application/json' },
        session_store: nil }
    }
    subject { get '/private', nil, { 'HTTP_CONTENT_TYPE' => 'application/json' } }
    its(:status) { should eql 401 }
    its(:body) { should eql 'Authorization Required' }
    it 'should not continue the execution' do
      expect_any_instance_of(CASRequest).to_not receive(:ticket_validation?)
      subject
    end
  end

  describe 'ignore 401 intercept' do
    let(:app_options) {
      { ignore_intercept_validator: Proc.new { |req| req.env['HTTP_CONTENT_TYPE'] == 'application/json' },
        session_store: nil }
    }
    subject { get '/private', nil, { 'HTTP_CONTENT_TYPE' => 'application/json' } }
    its(:status) { should eql 401 }
    its(:body) { should eql 'Authorization Required' }
  end

  describe 'auth required request' do
    describe 'without service configured' do
      subject { get '/private' }
      its(:status) { should eql 302 }
      its(:location) { should match %r{http://example.com/cas/login\?service=http%3A%2F%2Fexample.org%2Fprivate} }
    end

    describe 'with service configured' do
      let(:app_options) { { 'fake' => false, service: 'https://example.info' } }
      subject { get '/private' }
      its(:status) { should eql 302 }
      its(:location) { should match %r{http://example.com/cas/login\?service=https%3A%2F%2Fexample.info%2Fprivate} }
    end
  end
end
