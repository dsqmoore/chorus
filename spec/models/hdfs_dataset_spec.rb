require "spec_helper"

describe HdfsDataset do
  let(:dataset) { datasets(:hadoop) }
  let(:user) { users(:owner) }

  describe 'validations' do
    it { should validate_presence_of :file_mask }
    it { should belong_to(:hdfs_data_source) }
    it { should belong_to(:workspace) }
    it { should validate_presence_of(:workspace) }

    describe 'can only be created in an active workspace' do
      let(:dataset) { FactoryGirl.build(:hdfs_dataset) }

      context 'if the workspace is archived' do
        let(:workspace) { workspaces(:archived) }

        it 'produces an error' do
          dataset.workspace_id = workspace.id
          expect  {
            dataset.save!
          }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end

      context 'produces no errors if the workspace is not archived' do
        let(:workspace) { workspaces(:empty_workspace) }

        it 'produces no error' do
          dataset.update_attributes(:workspace_id => workspace.id)
          dataset.should_not have_error_on(:dataset)
        end
      end
    end

    describe 'can only be updated if all workspaces are active' do
      context 'if the workspace is archived' do
        before do
          workspace = dataset.workspace
          workspace.archived = 'true'
          workspace.archiver = user
          workspace.save!
        end

        it 'still allows tagging' do
          dataset.tags << Tag.new(:name => "fancy tag")
          dataset.save!
          dataset.should_not have_error_on(:dataset)
        end

        it 'produces an error' do
          dataset.update_attributes({name: 'shenanigans'})
          dataset.should have_error_on(:dataset)
        end
      end

      context 'if the workspace is not archived' do
        it 'produces no error' do
          dataset.update_attributes({name: 'shenanigans'})
          dataset.should_not have_error_on(:dataset)
        end
      end
    end
  end

  describe 'execution_location' do
    it "returns the Dataset's Hadoop DataSource" do
      dataset.execution_location.should == dataset.hdfs_data_source
    end
  end

  describe 'associable?' do
    it 'is false' do
      dataset.should_not be_associable
    end
  end

  describe "in_workspace?" do
    context "when the dataset is not in the workspace" do
      let(:workspace) { workspaces(:empty_workspace) }

      it "returns false" do
        dataset.in_workspace?(workspace).should be_false
      end
    end

    context "when the dataset is in the workspace" do
      it "returns true" do
        dataset.in_workspace?(dataset.workspace).should be_true
      end
    end
  end

  describe '.assemble!' do
    let(:file_mask) {'foo/bat/bar'}
    let(:attributes) do
      {
          :file_mask => file_mask,
          :name => Faker::Name.name
      }
    end
    let(:data_source) { hdfs_data_sources(:hadoop) }
    let(:workspace)   { workspaces(:public) }
    let(:user)        { users(:owner) }

    it "creates a dataset associated with the given datasource & workspace" do
      # Method under test hidden in test setup, in 'let' block :dataset.
      dataset = HdfsDataset.assemble!(attributes, data_source, workspace)
      dataset.data_source.should == data_source
      dataset.workspace.should == workspace
      dataset.file_mask.should == file_mask
    end
  end

  describe 'contents' do
    let(:hdfs_data_source) { hdfs_data_sources(:hadoop) }
    before do
      any_instance_of(Hdfs::QueryService) do |h|
        stub(h).show(dataset.file_mask) { ["content"] }
      end
    end

    it "returns the contents of the hdfs dataset" do
      dataset.contents.should == ['content']
    end

    context "corrupted file in file mask" do
      before do
        any_instance_of(Hdfs::QueryService) do |h|
          stub(h).show(dataset.file_mask) { raise FileNotFoundError, "File not found on HDFS" }
        end
      end

      it "raises HdfsContentsError when not able to read the file" do
        expect {
          dataset.contents
        }.to raise_error(HdfsDataset::HdfsContentsError)
      end
    end
  end
end