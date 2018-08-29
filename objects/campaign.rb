# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'yaml'
require_relative 'pgsql'
require_relative 'lane'
require_relative 'list'

# Campaign.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Campaign
  attr_reader :id

  def initialize(id:, pgsql: Pgsql.new, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash
  end

  def list
    hash = @pgsql.exec(
      'SELECT list.* FROM list JOIN campaign ON campaign.list=list.id WHERE campaign.id=$1',
      [@id]
    )[0]
    List.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def lane
    hash = @pgsql.exec(
      'SELECT lane.* FROM lane JOIN campaign ON campaign.lane=lane.id WHERE campaign.id=$1',
      [@id]
    )[0]
    Lane.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def title
    yaml['title'] || 'unknown'
  end

  def yaml
    YAML.safe_load(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM campaign WHERE id=$1', [@id])[0]['yaml']
    )
  end

  def save_yaml(yaml)
    YAML.safe_load(yaml)
    @pgsql.exec('UPDATE campaign SET yaml=$1 WHERE id=$2', [yaml, @id])
    @hash = {}
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM campaign WHERE id=$1', [@id])[0]['active']) == 't'
  end

  def toggle
    @pgsql.exec('UPDATE campaign SET active=not(active) WHERE id=$1', [@id])
    @hash = {}
  end
end