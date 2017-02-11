require 'spec_helper'

describe SurroGate::Proxy do
  let(:socket) { IO.pipe.first }
  let(:left) { IO.pipe }
  let(:right) { IO.pipe }
  let(:str) { 'test' }
  let(:block) { :foo.to_proc }

  let(:selectors) { subject.instance_variable_get(:@selectors) }
  let(:reader) { subject.instance_variable_get(:@reader) }
  let(:writer) { subject.instance_variable_get(:@writer) }
  let(:thread) { subject.instance_variable_get(:@thread) }
  let(:logger) { Logger.new('/dev/null') }

  subject { described_class.new(logger) }

  describe '#push' do
    it 'calls the proxy method with the two arguments' do
      expect(subject).to receive(:proxy).with(left.first, right.last, nil)
      subject.push(left.first, right.last)
    end

    it 'returns with its arguments' do
      expect(subject.push(left.first, right.last)).to eq([left.first, right.last])
    end

    context 'block given' do
      it 'passes it further to #proxy' do
        expect(subject).to receive(:proxy).with(left.first, right.last, block)
        subject.push(left.first, right.last, &block)
      end
    end

    context 'socket already pushed to the proxy' do
      before { subject.push(left.first, right.last) }

      it 'raises an exception' do
        expect { subject.push(socket, right.last) }.to raise_error(SurroGate::ProxyError)
      end
    end
  end

  describe '#wait' do
    context 'internal thread is running' do
      before { subject.send(:thread_start) }

      it 'joins the internal thread' do
        expect(thread).to receive(:join)
        subject.wait
      end
    end

    context 'internal thread is not running' do
      it 'returns nil' do
        expect(subject.wait).to be_nil
      end
    end
  end

  describe '#alive?' do
    context 'internal thread is running' do
      before { subject.send(:thread_start) }

      it 'returns with true' do
        expect(subject.alive?).to be_truthy
      end
    end

    context 'internal thread is not running' do
      it 'returns with false' do
        expect(subject.alive?).to be_falsey
      end
    end
  end

  describe '#proxy' do
    it 'registers sockets for reading' do
      subject.send(:proxy, left.first, right.last)
      selectors.each do |selector|
        [left.first, right.last].each do |socket|
          expect(selector.registered?(socket)).to be_truthy
        end
      end
    end

    it 'starts the internal thread' do
      expect(subject).to receive(:thread_start)
      subject.send(:proxy, left.first, right.last)
    end

    describe 'disconnect' do
      before do
        subject.send(:proxy, left.first, right.last)
        left.first.close
      end

      it 'disconnects the other end' do
        subject.wait
        expect(right.last.closed?).to be_truthy
      end

      context 'with no remaining sockets' do
        it 'kills the internal thread' do
          subject.wait
          expect(thread).to be_nil
        end
      end

      context 'with remaining sockets' do
        before { subject.send(:proxy, IO.pipe.first, IO.pipe.last) }

        it 'keeps the internal thread running' do
          expect(subject).not_to receive(:thread_stop)
          sleep(0.1) # Give some time to the background thread
          expect(thread.alive?).to be_truthy
        end
      end
    end

    describe 'monitor.value.call' do
      let(:rmon) { reader.select.select { |monitor| monitor.io == left.first }.first }
      let(:wmon) { writer.select.select { |monitor| monitor.io == right.last }.first }

      before do
        allow(subject).to receive(:thread_start)
        subject.send(:proxy, left.first, right.last)
        allow(wmon).to receive(:writable?).and_return(writable)
        left.last.write(str)
      end

      context 'only read is possible' do
        let(:writable) { false }

        it 'not invokes transmit' do
          expect(subject).not_to receive(:transmit)
          rmon.value.call
        end

        it 'returns with nil' do
          expect(rmon.value.call).to be_nil
        end
      end

      context 'both read and write are possible' do
        let(:writable) { true }

        it 'invokes transmit' do
          expect(subject).to receive(:transmit).with(left.first, right.last, nil)
          rmon.value.call
        end

        it 'returns with not nil' do
          expect(rmon.value.call).to eq(str.length)
        end
      end
    end
  end

  describe '#transmit' do
    it 'transmits from left to right' do
      left.last.write(str)
      len = subject.send(:transmit, left.first, right.last, nil)
      expect(right.first.read(len)).to eq(str)
    end

    it 'cleans up both sockets' do
      left.last.close
      expect(subject).to receive(:cleanup).with(left.first, right.last)
      subject.send(:transmit, left.first, right.last, nil)
    end

    context 'block given' do
      it 'passes the block to #cleanup' do
        left.last.close
        expect(subject).to receive(:cleanup).with(left.first, right.last)
        subject.send(:transmit, left.first, right.last, block)
      end
    end
  end

  describe '#cleanup' do
    before do
      reader.register(socket, :r)
      writer.register(socket, :w)
    end

    it 'closes and deregisters a socket' do
      subject.send(:cleanup, socket)

      selectors.each do |selector|
        expect(selector.registered?(socket)).to be_falsey
      end
      expect(socket.closed?).to be_truthy
    end

    context 'block given' do
      it 'yields to the block' do
        expect { |b| subject.send(:cleanup, socket, &b) }.to yield_control
      end
    end

    context 'sockets remaining after cleanup' do
      before do
        reader.register(IO.pipe.first, :r)
      end

      it 'keeps the internal thread' do
        expect(subject).not_to receive(:thread_stop)
        subject.send(:cleanup, socket)
      end
    end

    context 'no sockets remaining after cleanup' do
      it 'stops the internal thread' do
        expect(subject).to receive(:thread_stop)
        subject.send(:cleanup, socket)
      end
    end
  end

  describe '#reactor' do
    before do
      allow(subject).to receive(:thread_start)
      subject.push(left.first, right.last)
      left.last.write(str)
    end

    it 'calls the monitor value' do
      reader.select(0.1) do |m|
        expect(m.value).to receive(:call)
      end
      subject.send(:reactor)
    end
  end
end
