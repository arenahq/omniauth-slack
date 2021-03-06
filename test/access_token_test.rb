require 'helper'

describe OmniAuth::Slack::OAuth2::AccessToken do
  def setup
    @access_token = OmniAuth::Slack::OAuth2::AccessToken.new(
      OmniAuth::Slack::OAuth2::Client.new('key','secret'),
      "ABC123DEF456",
      {'user' => {'id' => '11', 'name' => 'bill'}, 'team_id' => 33, 'team_name' => 'my team'}
    )
    
    @at_class = OmniAuth::Slack::OAuth2::AccessToken
    
    @scope_base = YAML.load_file(File.join(File.dirname(__FILE__), 'support/scope_base.yml'))
  end
  
  it 'defines getter methods for basic user data' do
    assert_equal 'bill', @access_token.user_name
    assert_equal 'my team', @access_token.team_name
  end
  
  it 'defines access_token to provide universal access for data-methods' do
    assert_equal @access_token, @access_token.access_token
  end
  
  
  describe 'user_id' do
    it "gets data from params['user'].to_h['id']" do
      assert_equal '11', @access_token.user_id
    end
    
    it "gets data from params['user_id']" do
      @access_token.params.replace({'user_id' => 'user-id-01'})
      assert_equal 'user-id-01', @access_token.user_id
    end
    
    it "gets data from params['authorizing_user'].to_h['user_id']" do
      @access_token.params.replace({'authorizing_user' => {'user_id' => 'user-id-02'}})
      assert_equal 'user-id-02', @access_token.user_id
    end
  end
  
  describe 'uid' do
    it 'gets concatenated user_id-team_id' do
      assert_equal '11-33', @access_token.uid
    end
  end
  
  describe 'is_app_token?' do
    it "is true when params['token_type'] == 'app'" do
      @access_token.params['token_type'] = 'app'
      assert_equal true, @access_token.is_app_token?
    end
    
    it "is true when token-string starts with xoxa" do
      @access_token.token.replace 'xoxa-L1234-ABCD-5678-XXZZ'
      assert_equal true, @access_token.is_app_token?
    end
    
    it "is false when token-string starts with xoxp" do
      @access_token.token.replace 'xoxp-L1234-ABCD-5678-XXZZ'
      assert_equal false, @access_token.is_app_token?
    end
    
    it "is nil when no conditions are met" do
      assert_nil @access_token.is_app_token?
    end
  end
  
  describe 'is_identity_token?' do
    it "is true if params.user_id" do
      @access_token.params['user_id'] = 'abc'
      assert_equal true, @access_token.is_identity_token?
    end
    
    it "is true if params.user.id" do
      @access_token.params['user'] = {'id' => 'efg'}
      assert_equal true, @access_token.is_identity_token?
    end
    
    it "is false if not true" do
      @access_token.params.clear
      assert_equal false, @access_token.is_identity_token?
    end
  end
  
  describe 'all_scopes' do
    it 'calls apps_permissions_users_list if passed a user_id' do
    end
  end
  
  describe 'has_scope?' do
  end
  
  describe 'self.has_scope?' do    
    it 'accepts a string of classic scopes to be matched against base-scopes containing :classic key' do
      assert_equal true, @at_class.has_scope?(scope_query:'identify,channels:read,chat:write:bot,users.profile:read', scope_base:@scope_base)
    end
    
    # it 'DOES NOT accept an array of strings of classic scopes to be matched against base-scopes containing :classic key' do
    #   assert_equal true, @at_class.has_scope?(scope_query:['identify', 'channels:read', 'chat:write:bot', 'users.profile:read'], scope_base:@scope_base)
    # end
    
    it 'accepts a scope_query hash' do
      assert_equal true, @at_class.has_scope?(scope_query:{channel:'channelss:read im:read', group:'chat:write'}, scope_base:@scope_base)
    end
    
    it 'accepts an array of scope_query hashes' do
      assert_equal true, @at_class.has_scope?(scope_query:[{channel:'channelss:read im:read', group:'chat:write'}, {app_home:'chat:write'}], scope_base:@scope_base)
    end

    it 'accepts a scope_query hash with array of string values' do
      assert_equal true, @at_class.has_scope?(scope_query:{channel: %w(channelss:read im:read chat:write)}, scope_base:@scope_base)
    end
    
    it "accepts a :logic param to switch to 'and' (all) logic from 'or' (any) logic" do
      assert_equal false, @at_class.has_scope?(scope_query:{channel:'channels:read im:read', group:'chat:write'}, scope_base:@scope_base, logic:'and')
      assert_equal true, @at_class.has_scope?(scope_query:{channel:'channels:read im:read', group:'chat:write'}, scope_base:@scope_base, logic:'or')
      assert_equal false, @at_class.has_scope?(scope_query:{channel:'im:read'}, scope_base:@scope_base)
    end
    
    it "given 'or' logic, must match at least one scope from given scope_query hash" do
      assert_equal true, @at_class.has_scope?(scope_query:{channel:'channels:read im:read', group:'chat:wrong'}, scope_base:@scope_base, logic:'or')
      assert_equal false, @at_class.has_scope?(scope_query:{channel:'chappels:read im:read', group:'chat:wrong'}, scope_base:@scope_base, logic:'or')
    end
    
    it "given 'and' logic, must match all scopes from given scope_query hash" do
      assert_equal true, @at_class.has_scope?(scope_query:{channel:'channels:read channels:history', group:'chat:write'}, scope_base:@scope_base, logic:'and')
      assert_equal false, @at_class.has_scope?(scope_query:{channel:'channels:read channels:history', group:'chat:write', team:'users:read'}, scope_base:@scope_base, logic:'and')
    end
    
    it "logic for array of query hashes is opposite of logic for query-hash" do
      assert_equal true, @at_class.has_scope?(scope_query:[{channel:'channels:read im:read'}, {group:'chat:write'}], scope_base:@scope_base, logic:'and')
      assert_equal false, @at_class.has_scope?(scope_query:[{channel:'channels:read im:read'}, {group:'chat:wrong chat:still.wrong'}], scope_base:@scope_base, logic:'or')
    end
  end
end