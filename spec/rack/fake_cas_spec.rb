require 'spec_helper'

describe Rack::FakeCAS do
  def app
    fake_cas_test_app
  end

  describe 'public request' do
    subject { get '/public' }
    its(:status) { should eql 200 }
    its(:body) { should_not match /email/ }
    its(:body) { should_not match /password/ }
  end

  describe 'auth required request' do
    before do
      described_class.class_variable_set('@@cas_session', nil)
    end

    subject { get '/private' }
    it { should be_redirect }
    its(:location) { should eql 'http://example.org/login?service=http://example.org/private' }
    its(:headers) { }
  end

  describe 'login request' do
    before do
      described_class.class_variable_set('@@cas_session', cas_session)
      get '/login', { email: 'janed0@gmail.com', service: 'http://example.org/private' }, **headers
    end

    context 'ajax request' do
      let(:headers){ { 'X-Requested-With' => 'XMLHttpRequest' } }

      context 'without cas session' do
        let(:cas_session){ nil }

        subject { last_response }
        its(:status) { should eql 401 }
        its(:body) { should be_nil.or be_empty }

        describe 'session' do
          subject { last_request.session['cas'] }
          it { should be_nil }
        end
      end

      context 'with cas session' do
        let(:cas_session) do
          {
            email: 'janed0@gmail.com'
          }
        end

        subject { last_response }
        it { should be_redirect }
        its(:location) { should eql 'http://example.org/private?ticket=some-value' }

        describe 'session' do
          subject { last_request.session['cas'] }
          it { should be_nil }
        end
      end
    end

    context 'non ajax request' do
      let(:headers){ {} }

      context 'without cas session' do
        let(:cas_session){ nil }

        subject { last_response }
        its(:status) { should eql 200 }
        its(:body) { should match /email/ }
        its(:body) { should match /password/ }

        describe 'session' do
          subject { last_request.session['cas'] }
          it { should be_nil }
        end
      end

      context 'with cas session' do
        let(:cas_session) do
          {
            email: 'janed0@gmail.com'
          }
        end

        subject { last_response }
        it { should be_redirect }
        its(:location) { should eql 'http://example.org/private?ticket=some-value' }

        describe 'session' do
          subject { last_request.session['cas'] }
          it { should be_nil }
        end
      end
    end
  end

  describe 'login request' do
    before do
      described_class.class_variable_set('@@cas_session', nil)
      get '/logged_in', email: 'janed0@gmail.com', service: 'http://example.org/private'
    end

    subject { last_response }
    it { should be_redirect }
    its(:location) { should eql 'http://example.org/private' }

    describe 'session' do
      subject { last_request.session['cas'] }
      it { should be_nil }
    end

    it 'should have cas_session class variable set' do
      expect(described_class.class_variable_get('@@cas_session')).to eq(email: 'janed0@gmail.com')
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
                          'janed0@gmail.com' => {
                            'name' => 'Jane Doe',
                            'email2' => 'janed0@example.com'}
                        })
    end

    before do
      described_class.class_variable_set('@@cas_session', { email: 'janed0@gmail.com' })
      get '/private', ticket: 'some-value'
    end

    describe 'session' do
      subject { last_request.session['cas'] }
      it { should_not be_nil }
      its(['extra_attributes']) { should eql({'name' => 'Jane Doe',
                                              'email2' => 'janed0@example.com'}) }
    end
  end

  describe 'cas session mocking' do

    context 'default email' do
      subject{ described_class.mock_cas_session! }

      it 'sets cas_session clas variable' do
        subject
        expect(described_class.class_variable_get('@@cas_session')).to eq(email: 'email@example.com')
      end
    end

    context 'with provided email' do
      subject{ described_class.mock_cas_session!(email: 'provided@email.com') }

      it 'sets cas_session clas variable' do
        subject
        expect(described_class.class_variable_get('@@cas_session')).to eq(email: 'provided@email.com')
      end
    end

  end

  describe 'cas session unmocking' do

    subject{ described_class.unmock_cas_session! }

    before do
      described_class.class_variable_set('@@cas_session', { email: 'some.email@example.com' })
    end

    it 'sets cas_session clas variable' do
      subject
      expect(described_class.class_variable_get('@@cas_session')).to be_nil
    end

  end
end
