require 'spec_helper'

describe SurroGate::Selector do
  subject { described_class.new(logger) }

  let(:logger) { double }
  let(:pairing) { subject.instance_variable_get(:@pairing) }
  let(:left_pair) { pairing.find { |pair| pair.instance_variable_get(:@left) == sockpair.first } }
  let(:right_pair) { pairing.find { |pair| pair.instance_variable_get(:@right) == sockpair.first } }
  let(:sockpair) { Socket.pair(:UNIX, :DGRAM, 0) }
  let(:pipe) { IO.pipe }

  describe '#push' do
    context 'repushing arguments' do
      it 'raises an ArgumentError' do
        subject.push(*sockpair)
        expect { subject.push(*sockpair) }.to raise_error(ArgumentError)
      end
    end

    context 'invalid arguments' do
      let(:sockpair) { [nil, nil] }

      it 'raises a TypeError' do
        expect { subject.push(*sockpair) }.to raise_error(TypeError)
      end
    end

    it 'stores the socket pair' do
      expect(pairing.length).to eq(0)
      subject.push(*sockpair)
      expect(pairing.length).to eq(2)
    end
  end

  describe '#pop' do
    before { subject.push(*sockpair) }

    it 'removes the socket pair' do
      expect(pairing.length).to eq(2)
      subject.pop(*sockpair)
      expect(pairing.length).to eq(0)
    end

    it 'handles out of order cleanup' do
      subject.push(*pipe)
      subject.pop(*sockpair)

      expect { subject.select(500) }.to_not raise_error
     end
  end

  describe '#select' do
    before { subject.push(*sockpair) }

    context 'no sockets pushed' do
      before { subject.pop(*sockpair) }

      it 'returns zero' do
        expect(subject.select(1)).to eq(0)
      end
    end

    context 'empty sockets' do
      it 'event count' do
        expect(subject.select(1)).to eq(2)
        expect(subject.select(1)).to eq(0)
      end

      it 'sets pairs ready for writing' do
        subject.select(1)
        expect(left_pair.instance_variable_get(:@wr_rdy)).to be_truthy
        expect(right_pair.instance_variable_get(:@wr_rdy)).to be_truthy
      end
    end

    context 'one socket ready for reading' do
      it 'event count' do
        expect(subject.select(1)).to eq(2)
        sockpair.first.write_nonblock(0)
        expect(subject.select(1)).to eq(1)
        expect(subject.select(1)).to eq(0)
      end

      it 'sets one socket ready for reading' do
        sockpair.first.write_nonblock(0)
        subject.select(1)
        expect(right_pair.instance_variable_get(:@rd_rdy)).to be_truthy
      end
    end

    context 'both sockets ready for reading' do
      it 'event count' do
        expect(subject.select(1)).to eq(2)
        sockpair.first.write_nonblock(0)
        expect(subject.select(1)).to eq(1)
        sockpair.last.write_nonblock(0)
        expect(subject.select(1)).to eq(1)
        expect(subject.select(1)).to eq(0)
      end

      it 'sets both sockets ready for reading' do
        sockpair.first.write_nonblock(0)
        sockpair.last.write_nonblock(0)
        subject.select(1)
        expect(right_pair.instance_variable_get(:@rd_rdy)).to be_truthy
        expect(left_pair.instance_variable_get(:@rd_rdy)).to be_truthy
      end
    end
  end

  describe '#each_ready' do
    before { subject.push(*sockpair) }

    context 'no select was called' do
      it 'does nothing' do
        expect(left_pair.ready?).to be_falsey
        expect(right_pair.ready?).to be_falsey
        expect { |b| subject.each_ready(&b) }.not_to yield_control
        expect(left_pair.ready?).to be_falsey
        expect(right_pair.ready?).to be_falsey
      end
    end

    context 'select called, but no transmission' do
      it 'does nothing' do
        expect(left_pair.ready?).to be_falsey
        expect(right_pair.ready?).to be_falsey
        subject.select(1)
        expect { |b| subject.each_ready(&b) }.not_to yield_control
        expect(left_pair.ready?).to be_falsey
        expect(right_pair.ready?).to be_falsey
      end
    end

    context 'one direction ready for transmission' do
      it 'resets the readiness' do
        sockpair.first.write_nonblock(0)
        subject.select(1)
        expect(right_pair.ready?).to be_truthy
        expect { |b| subject.each_ready(&b) }.to yield_control.once
        expect(right_pair.ready?).to be_falsey
      end
    end

    context 'both directions ready for transmission' do
      it 'resets the readiness' do
        sockpair.first.write_nonblock(0)
        sockpair.last.write_nonblock(0)
        subject.select(1)
        expect(left_pair.ready?).to be_truthy
        expect(right_pair.ready?).to be_truthy
        expect { |b| subject.each_ready(&b) }.to yield_control.twice
        expect(left_pair.ready?).to be_falsey
        expect(right_pair.ready?).to be_falsey
        subject.select(1)
        expect(left_pair.ready?).to be_truthy
        expect(right_pair.ready?).to be_truthy
      end
    end
  end
end
