require 'spec_helper'

describe Rack::FakeCAS do
  def app
    fake_cas_test_app
  end

  describe 'public request' do
    subject { get '/public' }
    its(:status) { should eql 200 }
    its(:body) { should_not match /username/ }
    its(:body) { should_not match /password/ }
  end

  describe 'auth required request' do
    before do
      described_class.class_variable_set('@@cas_session_present', false)
    end

    subject { get '/private' }
    it { should be_redirect }
    its(:location) { should eql 'http://example.org/login?service=http://example.org/private' }
    its(:headers) { }
  end

  describe 'fake_cas_login request' do
    before do
      described_class.class_variable_set('@@cas_session_present', cas_session_present)
      get '/login', username: 'janed0', service: 'http://example.org/private'
    end

    context 'without cas session' do
      let(:cas_session_present){ false }

      subject { last_response }
      its(:status) { should eql 200 }
      its(:body) { should match /username/ }
      its(:body) { should match /password/ }

      describe 'session' do
        subject { last_request.session['cas'] }
        it { should be_nil }
      end
    end

    context 'with cas session' do
      let(:cas_session_present){ true }

      subject { last_response }
      it { should be_redirect }
      its(:location) { should eql 'http://example.org/private?ticket=some-value' }

      describe 'session' do
        subject { last_request.session['cas'] }
        it { should be_nil }
      end
    end

  end

  describe 'login request' do
    before do
      described_class.class_variable_set('@@cas_session_present', false)
      get '/logged_in', username: 'janed0', service: 'http://example.org/private'
    end

    subject { last_response }
    it { should be_redirect }
    its(:location) { should eql 'http://example.org/private' }

    describe 'session' do
      subject { last_request.session['cas'] }
      it { should be_nil }
    end

    it 'should have cas_session_present class variable set to true' do
      expect(described_class.class_variable_get('@@cas_session_present')).to be(true)
      subject
    end
  end

  describe 'ticket validation request' do
    before { get '/private', ticket: 'some-value' }

    subject { last_response }
    it { should be_redirect }
    its(:location) { should eql 'http://example.org/private' }
    its(:headers) { }

    describe 'session' do
      subject { last_request.session['cas'] }
      it { should_not be_nil }
    end
  end

  describe 'logout request' do
    before { get '/logout' }

    subject { last_response }
    it { should be_redirect }
    its(:location) { should eql '/'}

    describe 'session' do
      subject { last_request.session }
      it { should eql({}) }
    end
  end

  describe 'excluded request' do
    def app
      Rack::FakeCAS.new(CasTestApp.new, exclude_path: '/private')
    end

    subject { get '/private' }
    its(:status) { should eql 401 }
    its(:body) { should eql 'Authorization Required' }
  end

  describe 'extra attributes' do
    def app
      Rack::FakeCAS.new(CasTestApp.new, {}, {
                          'janed0' => {
                            'name' => 'Jane Doe',
                            'email' => 'janed0@gmail.com'}
                        })
    end

    before do
      described_class.class_variable_set('@@cas_session_present', true)
      get '/private', username: 'janed0', ticket: 'some-value'
    end

    describe 'session' do
      subject { last_request.session['cas'] }
      it { should_not be_nil }
      its(['extra_attributes']) { should eql({'name' => 'Jane Doe',
                                              'email' => 'janed0@gmail.com'}) }
    end
  end
end
