# :markup: tomdoc

require 'oauth2/access_token'
require 'omniauth-slack/refinements'
require 'omniauth-slack/data_methods'
require 'omniauth-slack/debug'

module OmniAuth
  module Slack
    using StringRefinements
    
    module OAuth2
      # Enhanced subclass of OAuth2::AccessToken, used by OmniAuth::Slack
      # whenever an OAuth2::AccessToken is required.
      #
      # Adds class and instance scope-query method +has_scope?+, and adds
      # basic API data methods and access methods.
      class AccessToken < ::OAuth2::AccessToken        
        include OmniAuth::Slack::DataMethods
        include OmniAuth::Slack::Debug

        # AccessToken instance (self), so Strategy data-methods can be copied to AccessToken without modification.
        def access_token; self; end

        # Creates simple getter methods to pull specific data from params.
        %w(user_name user_email team_id team_name team_domain).each do |word|
          obj, atrb = word.split('_')
          define_method(word) do
            params[word] ||
            params[obj].to_h[atrb]
          end
        end

        # Cannonical AccessToken user_id.
        def user_id
          params['user_id'] ||
          params['user'].to_h['id'] ||
          params['authorizing_user'].to_h['user_id']
        end
        
        # Cannonical AccessToken unique user-team-id combo.
        def uid
          "#{user_id}-#{team_id}"
        end
      
        # Is this a workspace app token?
        #
        # Returns nil if unknown
        def is_app_token?
          case
            when params['token_type'] == 'app' || token.to_s[/^xoxa/]
              true
            when token.to_s[/^xoxp/]
              false
            else
              nil
          end
        end
        
        # Is this a token returned from an identity-scoped request?
        def is_identity_token?
          (params['user_id'] ||
          params['user'].to_h['id']) && true || false
        end
      
        # Identity scopes (workspace apps only).
        # Given _user_id, returns specific identity scopes.
        #
        # Sets @apps_permissions_users_list with parsed API response.
        #
        # _user_id  - String of Slack user ID.
        #
        def apps_permissions_users_list(_user_id=nil)
          #raise StandardError, "APUL caller #{caller_method_name} user #{_user_id}"
          return {} unless is_app_token?
          semaphore.synchronize {
            @apps_permissions_users_list ||= (
              r = get('/api/apps.permissions.users.list').parsed
              r['resources'].to_a.inject({}){|h,i| h[i['id']] = i; h} || {}
            )
            _user_id ? @apps_permissions_users_list[_user_id].to_h['scopes'] : @apps_permissions_users_list
          }
        end
        
        # Hash of current scopes for this token (workspace apps only).
        # Sets +@apps_permissions_scopes_list+ with parsed API response.
        def apps_permissions_scopes_list
          return {} unless is_app_token?
            semaphore.synchronize {
            @apps_permissions_scopes_list ||= (
              r = get('/api/apps.permissions.scopes.list').parsed
              r['scopes'] || {}
            )
          }
        end
                
        # Compiles scopes awarded to this AccessToken.
        # Given _user_id, includes +apps.permissions.users.list+.
        #
        # Sets +@all_scopes+ with parsed API response.
        #
        # This now puts all compiled scopes back into <tt>params['scopes']</tt>.
        # 
        # _user_id  - String of Slack user ID.
        #
        # Returns Hash of scope Arrays where *key* is scope section
        # and *value* is Array of scopes.
        #
        def all_scopes(_user_id=nil)
          debug{"_user_id: #{_user_id}, @all_scopes: #{@all_scopes}"}
          if _user_id && !@all_scopes.to_h.has_key?('identity') || @all_scopes.nil?
            @all_scopes = (
              scopes = case
                when params['scope']
                  {'classic' => params['scope'].words}
                when params['scopes']
                  params['scopes']
                when is_app_token?
                  apps_permissions_scopes_list
              end
              
              scopes['identity'] = apps_permissions_users_list(_user_id) if _user_id && is_app_token?
              params['scopes'] = scopes
            )
          else
            @all_scopes
          end
        end
        
        # Match a given set of scopes against this token's awarded scopes,
        # classic and workspace token compatible.
        #
        # If the scope-query is a string, it will be interpreted as a Slack Classic App
        # scope string +{classic: scope-query-string}+.
        #
        # The keywords need to be symbols, so any hash passed as an argument
        # (or as the entire set of args) should have symbolized keys!
        #
        # freeform_array    - [*Array, nil] default: [], array of scope query hashes
        #
        # :query            - [Hash, Array, nil] default: nil, a single scope-query Hash (or Array of Hashes)
        #
        # :logic            - [String, Symbol] default: 'or' [:or | :and] logic for the scope-query.
        #                     Applies to a single query hash.
        #                     The reverse logic is applied to an array of query hashes.
        #
        # :user             - [String] (nil) default: nil, user_id of the Slack user to query against
        #                     leave blank for non-user queries
        #
        # :base             - [Hash] default: nil, a set of scopes to query against
        #                     defaults to the awarded scopes on this token
        #
        # freeform_hash     - [**Hash] default: {}, interpreted as single scope query hash
        #
        # TODO: Does this accept all slack token types? What about bot tokens? Others?
        #
        def has_scope?(*freeform_array, query: nil, logic:'or', user:nil, base:nil, **freeform_hash)
          debug{{freeform_array:freeform_array, freeform_hash:freeform_hash, query:query, logic:logic, user:user, base:base}}
          #OmniAuth.logger.debug({freeform_array:freeform_array, freeform_hash:freeform_hash, query:query, logic:logic, user:user, base:base})
          
          query ||= case
            when freeform_array.any?; freeform_array
            when freeform_hash.any?; freeform_hash
          end
          return unless query
          
          query = [query].flatten if query.is_a?(Array)
          user ||= user_id
          debug{"using user '#{user}' and query '#{query}'"}
          
          is_identity_query = case query
            when Hash
              query.keys.detect{|k| k.to_s == 'identity'}
            when Array
              query.detect{ |q| q.is_a?(Hash) && q.keys.detect{|k| k.to_s == 'identity'} }
          end
          
          base ||= case
            when user && is_identity_query
              debug{"calling all_scopes(user=#{user}) to build base-scopes"}
              all_scopes(user)
            else
              debug{"calling all_scopes to build base-scopes"}
              all_scopes
          end
          
          #debug{{freeform_array:freeform_array, freeform_hash:freeform_hash, query:query, logic:logic, user:user, base:base}}
          self.class.has_scope?(scope_query:query, scope_base:base, logic:logic)
        end
        
        # Matches the given scope_query against the given scope_base, with the given logic.
        #
        # This is classic and workspace token compatible.
        #
        # keywords      - All arguments are keyword arguments:
        #
        # :scope_query  - [Hash, Array of hashes] default: {}.
        #                 If scope_query is a string, it will be interpreted as +{classic: scope-query-string}+.
        #
        #                 key    - Symbol of scope type <app_home|team|channel|group|mpim|im|identity|classic>
        #                 value  - Array or String of individual scopes
        #
        # :scope_base   - [Hash] defaul: {}, represents the set of scopes to query against.
        #
        # :logic        - [String, Symbol] default: or. One of <and|or>.
        #                 Applies to a single query hash.
        #                 The reverse logic is applied to an array of query hashes.
        #
        # Examples
        #                 
        #   has_scope?(scope_query: {channel: 'channels:read chat:write'})
        #   has_scope?(scope_query: [{identity:'uers:read', channel:'chat:write'}, {app_home:'chat:write'}], logic:'and')
        #   has_scope?(scope_query: 'identity:users identity:team identity:avatar')
        #
        # TODO: Remove any code specific to Slack, like classic-vs-workspace handling.
        #
        # TODO: Can this be added to OAuth2::AccessToken as a generic has_scope? Would it work for other providers?
        # It ~should~ work for other providers, according to oauth2 spec https://tools.ietf.org/html/rfc6749#section-3.3
        #
        def self.has_scope?(scope_query:{}, scope_base:{}, logic:'or')
          debug{"class-level-has_scope? scope_query '#{scope_query}' scope_base '#{scope_base}' logic '#{logic}'"}
          _scope_query = scope_query.is_a?(String) ? {classic: scope_query} : scope_query
          _scope_query = [_scope_query].flatten
          _scope_base  = scope_base
          raise "scope_base must be a hash" unless (_scope_base.is_a?(Hash) || _scope_base.respond_to?(:to_h))
          
          _logic = case
            when logic.to_s.downcase == 'or'; {outter: 'all?', inner: 'any?'}
            when logic.to_s.downcase == 'and'; {outter: 'any?', inner: 'all?'}
            else {outter: 'all?', inner: 'any?'}
          end
          debug{"logic #{_logic.inspect}"}
          
          _scope_query.send(_logic[:outter]) do |query|
            debug{"outter query: #{_scope_query.inspect}"}

            query.send(_logic[:inner]) do |section, scopes|
              test_scopes = case
                when scopes.is_a?(String); scopes.words
                when scopes.is_a?(Array); scopes
                else raise "Scope data must be a string or array of strings, like this {team: 'chat:write,team:read', channels: ['channels:read', 'chat:write']}"
              end
              
              test_scopes.send(_logic[:inner]) do |scope|
                debug{"inner query section: #{section.to_s}, scope: #{scope}"}
                _scope_base.to_h[section.to_s].to_a.include?(scope.to_s)
              end
            end
            
          end # scope_query.each
        end # self.has_scope?
        
      end # AccessToken
    end
  end
end