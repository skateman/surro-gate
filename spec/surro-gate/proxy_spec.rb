require 'spec_helper'

describe SurroGate::Proxy do
  let(:socket) { IO.pipe.first }
  let(:left) { IO.pipe }
  let(:right) { IO.pipe }
  let(:str) { 'test' }
  let(:block) { :foo.to_proc }

  let(:selector) { subject.instance_variable_get(:@selector) }
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
      expect(selector.registered?(left.first)).to be_truthy
      expect(selector.registered?(right.last)).to be_truthy
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
      let(:monitors) { selector.select }
      let(:reader) { monitors.select(&:readable?).first }
      let(:writer) { monitors.select(&:writable?).first }

      before do
        subject.send(:proxy, left.first, right.last)
        subject.send(:thread_stop)
      end

      context 'transmission is possible' do
        before { left.last.write(str) }

        it 'invokes transmit' do
          expect(subject).to receive(:transmit).with(reader.io, writer.io, nil)
          reader.value.call
        end

        it 'returns with a number' do
          expect(reader.value.call).to be > 0
        end
      end

      context 'transmission is not possible' do
        it 'does not invoke transmit' do
          expect(subject).not_to receive(:transmit)
          writer.value.call
        end

        it 'returns with nil' do
          selector.select do |monitor|
            expect(monitor.value.call).to be_nil
          end
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
      selector.register(socket, :r)
    end

    it 'closes and deregisters a socket' do
      subject.send(:cleanup, socket)
      expect(selector.registered?(socket)).to be_falsey
      expect(socket.closed?).to be_truthy
    end

    context 'block given' do
      it 'yields to the block' do
        expect { |b| subject.send(:cleanup, socket, &b) }.to yield_control
      end
    end

    context 'sockets remaining after cleanup' do
      before do
        selector.register(IO.pipe.first, :r)
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
    context 'no sockets are registered' do
      it 'does not sleep' do
        expect(subject).not_to receive(:sleep)
        subject.send(:reactor)
      end
    end

    context 'registered sockets' do
      before do
        subject.push(left.first, right.last)
        subject.send(:thread_stop)
      end

      context 'not ready for IO' do
        it 'sleeps' do
          expect(subject).to receive(:sleep)
          subject.send(:reactor)
        end
      end

      context 'ready for IO' do
        before { left.last.write(str) }

        it 'calls the monitor value' do
          selector.select(0) do |m|
            expect(m.value).to receive(:call)
          end
          subject.send(:reactor)
        end
      end
    end
  end
end
