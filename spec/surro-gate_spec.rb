require 'spec_helper'

describe SurroGate do
  describe '#new' do
    it 'returns with an instance of Proxy' do
      expect(subject.new).to be_an_instance_of(SurroGate::Proxy)
    end
  end
end
