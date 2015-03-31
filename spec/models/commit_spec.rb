# == Schema Information
#
# Table name: commits
#
#  id         :integer          not null, primary key
#  project_id :integer
#  ref        :string(255)
#  sha        :string(255)
#  before_sha :string(255)
#  push_data  :text
#  created_at :datetime
#  updated_at :datetime
#

require 'spec_helper'

describe Commit do
  let(:project) { FactoryGirl.create :project }
  let(:commit) { FactoryGirl.create :commit, project: project }
  let(:commit_with_project) { FactoryGirl.create :commit, project: project }

  it { should belong_to(:project) }
  it { should have_many(:builds) }
  it { should validate_presence_of :before_sha }
  it { should validate_presence_of :sha }
  it { should validate_presence_of :ref }
  it { should validate_presence_of :push_data }

  it { should respond_to :git_author_name }
  it { should respond_to :git_author_email }
  it { should respond_to :short_sha }

  it { should allow_mass_assignment_of(:project_id) }
  it { should allow_mass_assignment_of(:ref) }
  it { should allow_mass_assignment_of(:sha) }
  it { should allow_mass_assignment_of(:before_sha) }
  it { should allow_mass_assignment_of(:push_data) }
  it { should allow_mass_assignment_of(:status) }
  it { should allow_mass_assignment_of(:project_name) }

  describe :last_build do
    subject { commit.last_build }
    before do
      @first = FactoryGirl.create :build, commit: commit, created_at: Date.yesterday
      @second = FactoryGirl.create :build, commit: commit
    end

    it { should be_a(Build) }
    it('returns with the most recently created build') { should eq(@second) }
  end

  describe :retry do
    before do
      @first = FactoryGirl.create :build, commit: commit, created_at: Date.yesterday
      @second = FactoryGirl.create :build, commit: commit
    end

    it "creates new build" do
      expect(commit.builds.count(:all)).to eq 2
      commit.retry
      expect(commit.builds.count(:all)).to eq 3
    end
  end

  describe :ci_skip? do
    let(:project) { FactoryGirl.create(:project) }
    let(:commit) { FactoryGirl.create(:commit, project: project) }

    it 'true if commit message contains [ci skip]' do
      commit.stub(:git_commit_message) { 'Small typo [ci skip]' }
      commit.ci_skip?.should == true
    end

    it 'false if commit message does not contain [ci skip]' do
      commit.ci_skip?.should == false
    end
  end

  describe :project_recipients do

    context 'always sending notification' do
      it 'should return commit_pusher_email as only recipient when no additional recipients are given' do
        project = FactoryGirl.create :project,
          email_add_pusher: true,
          email_recipients: ''
        commit =  FactoryGirl.create :commit, project: project
        expected = 'commit_pusher_email'
        commit.stub(:push_data) { { user_email: expected } }
        commit.project_recipients.should == [expected]
      end

      it 'should return commit_pusher_email and additional recipients' do
        project = FactoryGirl.create :project,
          email_add_pusher: true,
          email_recipients: 'rec1 rec2'
        commit = FactoryGirl.create :commit, project: project
        expected = 'commit_pusher_email'
        commit.stub(:push_data) { { user_email: expected } }
        commit.project_recipients.should == ['rec1', 'rec2', expected]
      end

      it 'should return recipients' do
        project = FactoryGirl.create :project,
          email_add_pusher: false,
          email_recipients: 'rec1 rec2'
        commit = FactoryGirl.create :commit, project: project
        commit.project_recipients.should == ['rec1', 'rec2']
      end

      it 'should return unique recipients only' do
        project = FactoryGirl.create :project,
          email_add_pusher: true,
          email_recipients: 'rec1 rec1 rec2'
        commit = FactoryGirl.create :commit, project: project
        expected = 'rec2'
        commit.stub(:push_data) { { user_email: expected } }
        commit.project_recipients.should == ['rec1', 'rec2']
      end
    end
  end

  describe :valid_commit_sha do
    context 'commit.sha can not start with 00000000' do
      before do
        commit.sha = '0' * 40
        commit.valid_commit_sha
      end

      it('commit errors should not be empty') { commit.errors.should_not be_empty }
    end
  end

  describe :compare? do
    subject { commit_with_project.compare? }

    context 'if project.gitlab_url and commit.before_sha are not nil' do
      it { should be_true }
    end
  end

  describe :short_sha do
    subject { commit.short_before_sha }

    it { should have(8).items }
    it { commit.before_sha.should start_with(subject) }
  end

  describe :short_sha do
    subject { commit.short_sha }

    it { should have(8).items }
    it { commit.sha.should start_with(subject) }
  end

  describe :gitlab? do
    subject { commit_with_project.gitlab? }

    it { should eq(project.gitlab?) }
  end

  describe "create_deploy_builds" do
    it "creates deploy build for projects without test jobs" do
      FactoryGirl.create :job, job_type: :deploy, project: project
      project.reload

      commit.create_deploy_builds(commit.ref)
      commit.builds.reload

      commit.builds.size.should == 1
    end

    it "creates new build for deploy if all jobs succeed" do
      job = FactoryGirl.create :job, project: project
      job1 = FactoryGirl.create :job, project: project
      FactoryGirl.create :job, job_type: :deploy, project: project
      FactoryGirl.create :build, commit: commit, status: :success, job: job
      FactoryGirl.create :build, commit: commit, status: :success, job: job1
      project.reload

      commit.create_deploy_builds(commit.ref)

      commit.builds.size.should == 3
    end

    it "does not create deploy build if one job failed" do
      job = FactoryGirl.create :job, project: project
      job1 = FactoryGirl.create :job, project: project
      FactoryGirl.create :job, job_type: :deploy, project: project
      FactoryGirl.create :build, commit: commit, status: :failed, job: job
      FactoryGirl.create :build, commit: commit, status: :success, job: job1
      project.reload

      commit.create_deploy_builds(commit.ref)

      commit.builds.size.should == 2
    end
  end
end
