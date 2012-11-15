class Build < ActiveRecord::Base
  belongs_to :project

  attr_accessible :project_id, :ref, :sha,
    :status, :finished_at, :trace, :started_at

  validates :sha, presence: true
  validates :ref, presence: true
  validates :status, presence: true

  scope :latest_sha, where("id IN(SELECT MAX(id) FROM #{self.table_name} group by sha)")

  state_machine :status, initial: :pending do
    event :run do
      transition pending: :running
    end

    event :drop do
      transition running: :failed
    end

    event :success do
      transition running: :success
    end

    after_transition :pending => :running do |build, transition|
      build.update_attributes started_at: Time.now
    end

    after_transition :running => :any do |build, transition|
      build.update_attributes finished_at: Time.now
    end

    state :pending, value: 'pending'
    state :running, value: 'running'
    state :failed, value: 'failed'
    state :success, value: 'success'
  end

  def git_author_name
    project.last_commit(self.sha).author.name
  rescue
    nil
  end

  def write_trace(trace)
    self.reload
    update_attributes(trace: trace)
  end

  def short_sha
    sha[0..8]
  end

  def trace_html
    if trace.present?
      Ansi2html::convert(trace)
    else
      ''
    end
  end

  def to_param
    sha
  end
end


# == Schema Information
#
# Table name: builds
#
#  id          :integer(4)      not null, primary key
#  project_id  :integer(4)
#  ref         :string(255)
#  status      :string(255)
#  finished_at :datetime
#  trace       :text
#  created_at  :datetime        not null
#  updated_at  :datetime        not null
#  sha         :string(255)
#

