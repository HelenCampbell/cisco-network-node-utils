# Copyright (c) 2014-2015 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require File.join(File.dirname(__FILE__), 'node_util')

module Cisco
  # SnmpUser - node utility class for SNMP user configuration management
  class SnmpUser < NodeUtil
    def initialize(name, groups, authproto, authpass, privproto,
                   privpass, localizedkey, engineid, instantiate=true)
      initialize_validator(name, groups, authproto, authpass, privproto,
                           privpass, engineid, instantiate)
      @name = name
      @engine_id = engineid

      @authproto = authproto
      @privproto = privproto
      @groups_arr = groups

      authprotostr = _auth_sym_to_str(authproto)
      privprotostr = _priv_sym_to_str(privproto)

      return unless instantiate
      # Config string syntax:
      # [no] snmp-server user <user> [group] ...
      #      [auth {md5|sha} <passwd1>
      #       [priv [aes-128] <passwd2>] [localizedkey] [engineID <id>]
      #      ]
      # Assume if multiple groups, apply all config to each
      groups = [''] if groups.empty?
      groups.each do |group|
        config_set('snmp_user', 'user', '',
                   name,
                   group,
                   authpass.empty? ? '' : "auth #{authprotostr} #{authpass}",
                   privpass.empty? ? '' : "priv #{privprotostr} #{privpass}",
                   localizedkey ? 'localizedkey' : '',
                   engineid.empty? ? '' : "engineID #{engineid}")
      end
    end

    def initialize_validator(name, groups, authproto, authpass, privproto,
                             privpass, engineid, instantiate)
      fail TypeError unless name.is_a?(String) &&
                            groups.is_a?(Array) &&
                            authproto.is_a?(Symbol) &&
                            authpass.is_a?(String) &&
                            privproto.is_a?(Symbol) &&
                            privpass.is_a?(String) &&
                            engineid.is_a?(String)
      fail ArgumentError if name.empty?
      # empty password but protocol provided = bad
      # non-empty password and no protocol provided = bad
      if authpass.empty?
        fail ArgumentError if [:sha, :md5].include?(authproto) && instantiate
      else
        fail ArgumentError unless [:sha, :md5].include?(authproto)
      end
      if privpass.empty?
        fail ArgumentError if [:des, :aes128].include?(privproto) && instantiate
      else
        fail ArgumentError unless [:des, :aes128].include?(privproto)
      end
    end

    ENGINE_ID_PATTERN = /([0-9]{1,3}(:[0-9]{1,3}){4,31})/
    def self.users
      users_hash = {}
      # config_get returns hash if 1 user, array if multiple, nil if none
      users = config_get('snmp_user', 'user')
      return users_hash if users.nil?
      users = [users] if users.is_a?(Hash)
      users.each do |user|
        name = user['user']
        engineid = user['engineID']
        if engineid.nil?
          index = name
        else
          engineid_str = engineid.match(ENGINE_ID_PATTERN)[1]
          index = name + ' ' + engineid_str
        end
        auth = _auth_str_to_sym(user['auth'])
        priv = _priv_str_to_sym(user['priv'])

        groups_arr = []
        groups = _user_to_groups(user)
        groups.each { |group| groups_arr << group['group'].strip }

        users_hash[index] = SnmpUser.new(name, groups_arr, auth,
                                         '', priv, '', false,
                                         engineid.nil? ? '' : engineid_str,
                                         false)
      end
      users_hash
    end

    def destroy
      # The parser doesn't care what the real value is but need to come to the
      # end of the parser chain. Hence we just pass in some fake values for
      # auth method and password
      unless auth_password.nil? || auth_password.empty?
        auth_str = "auth #{_auth_sym_to_str(auth_protocol)} #{auth_password}"
        local_str = 'localizedkey'
      end
      unless priv_password.nil? || priv_password.empty?
        priv_str = "priv #{_priv_sym_to_str(priv_protocol)} #{priv_password}"
      end
      config_set('snmp_user', 'user', 'no',
                 @name, '', auth_str, priv_str, local_str,
                 @engine_id.empty? ? '' : "engineID #{@engine_id}")
      SnmpUser.users.delete(@name + ' ' + @engine_id)
    end

    attr_reader :name

    def groups
      @groups_arr
    end

    def self.default_groups
      [config_get_default('snmp_user', 'group')]
    end

    def auth_protocol
      @authproto
    end

    def self.default_auth_protocol
      _auth_str_to_sym(config_get_default('snmp_user', 'auth_protocol'))
    end

    def self.default_auth_password
      config_get_default('snmp_user', 'auth_password')
    end

    def self.auth_password(name, engine_id)
      if engine_id.empty?
        users = config_get('snmp_user', 'auth_password')
        return nil if users.nil?
        users.each_entry { |user| return user[1] if user[0] == name }
      else
        users = config_get('snmp_user', 'auth_password_with_engine_id')
        return nil if users.nil?
        users.each_entry do |user|
          return user[1] if user[0] == name && user[2] == engine_id
        end
      end
      nil
    end

    def auth_password
      SnmpUser.auth_password(@name, @engine_id)
    end

    def priv_protocol
      @privproto
    end

    def self.priv_password(name, engine_id)
      if engine_id.empty?
        users = config_get('snmp_user', 'priv_password')
        unless users.nil?
          users.each_entry { |user| return user[1] if user[0] == name }
        end
      else
        users = config_get('snmp_user', 'priv_password_with_engine_id')
        unless users.nil?
          users.each_entry do |user|
            return user[1] if user[0] == name && user[2] == engine_id
          end
        end
      end
      nil
    end

    def priv_password
      SnmpUser.priv_password(@name, @engine_id)
    end

    def self.default_priv_protocol
      _priv_str_to_sym(config_get_default('snmp_user', 'priv_protocol'))
    end

    def self.default_priv_password
      config_get_default('snmp_user', 'priv_password')
    end

    attr_reader :engine_id

    def self.default_engine_id
      config_get_default('snmp_user', 'engine_id')
    end

    # passwords are hashed and so cannot be retrieved directly, but can be
    # checked for equality. this is done by creating a fake user with the
    # password and then comparing the hashes
    def auth_password_equal?(passwd, is_localized=false)
      passwd = passwd.to_s unless passwd.is_a?(String)
      return true if passwd.empty? && _auth_sym_to_str(auth_protocol).empty?
      return false if passwd.empty? || _auth_sym_to_str(auth_protocol).empty?
      dummypw = passwd
      pw = nil

      if is_localized
        # In this case, the password is hashed. We only need to get current
        # running config to compare
        pw = auth_password
      else
        # In this case passed in password is clear text while the running
        # config is hashed value. We need to hash the
        # passed in clear text to hash

        # create dummy user
        config_set('snmp_user', 'user', '', 'dummy_user', '',
                   "auth #{_auth_sym_to_str(auth_protocol)} #{dummypw}",
                   '', '',
                   @engine_id.empty? ? '' : "engineID #{@engine_id}")

        # retrieve password hashes
        dummypw = SnmpUser.auth_password('dummy_user', @engine_id)
        pw = auth_password

        # delete dummy user
        config_set('snmp_user', 'user', 'no', 'dummy_user', '',
                   "auth #{_auth_sym_to_str(auth_protocol)} #{dummypw}",
                   '', 'localizedkey',
                   @engine_id.empty? ? '' : "engineID #{@engine_id}")
      end
      return false if pw.nil? || dummypw.nil?
      pw == dummypw
    end

    def priv_password_equal?(passwd, is_localized=false)
      passwd = passwd.to_s unless passwd.is_a?(String)
      return true if passwd.empty? && _auth_sym_to_str(auth_protocol).empty?
      return false if passwd.empty? || _auth_sym_to_str(auth_protocol).empty?
      dummypw = passwd
      pw = nil

      if is_localized
        # In this case, the password is hashed. We only need to get current
        # and compare directly
        pw = priv_password
      else
        # In this case passed in password is clear text while the running
        # config is hashed value. We need to hash the
        # passed in clear text to hash

        # create dummy user
        config_set('snmp_user', 'user', '', 'dummy_user', '',
                   "auth #{_auth_sym_to_str(auth_protocol)} #{dummypw}",
                   "priv #{_priv_sym_to_str(priv_protocol)} #{dummypw}",
                   '',
                   @engine_id.empty? ? '' : "engineID #{@engine_id}")

        # retrieve password hashes
        dummyau = SnmpUser.auth_password('dummy_user', @engine_id)
        dummypw = SnmpUser.priv_password('dummy_user', @engine_id)
        pw = priv_password

        # delete dummy user
        config_set('snmp_user', 'user', 'no', 'dummy_user', '',
                   "auth #{_auth_sym_to_str(auth_protocol)} #{dummyau}",
                   "priv #{_priv_sym_to_str(priv_protocol)} #{dummypw}",
                   'localizedkey',
                   @engine_id.empty? ? '' : "engineID #{@engine_id}")
      end
      return false if pw.nil? || dummypw.nil?
      pw == dummypw
    end

    private

    def _auth_sym_to_str(sym)
      case sym
      when :sha
        return 'sha'
      when :md5
        return 'md5'
      else
        return ''
      end
    end

    def _priv_sym_to_str(sym)
      case sym
      when :des
        return '' # no protocol specified defaults to DES
      when :aes128
        return 'aes-128'
      else
        return ''
      end
    end

    def _auth_str_to_sym(str)
      SnmpUser._auth_str_to_sym(str)
    end

    # must be class method b/c it's used by default methods
    def self._auth_str_to_sym(str)
      case str
      when /sha/i
        return :sha
      when /md5/i
        return :md5
      else
        return :none
      end
    end

    def _priv_str_to_sym(str)
      SnmpUser._priv_str_to_sym(str)
    end

    def self._priv_str_to_sym(str)
      case str
      when /des/i
        return :des
      when /aes/i
        return :aes128
      else
        return :none
      end
    end

    def self._user_to_groups(user_hash)
      return [] if user_hash.nil?
      groups = user_hash['TABLE_groups']['ROW_groups'] unless
        user_hash['TABLE_groups'].nil?
      return [] if groups.nil?
      groups = [groups] if groups.is_a?(Hash)
      groups
    end
  end
end
