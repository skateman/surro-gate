require 'spec_helper'

describe SurroGate::Proxy do
  let(:logger) { Logger.new('/dev/null') }
  let(:pair) { ::UNIXSocket.pair(:DGRAM, 0) }
  let(:sock_a) { pair.first }
  let(:sock_b) { pair.last }

  subject { described_class.new(logger) }

  describe '#cleanup' do
    context 'no cleanup block passed' do
      before { subject.send(:cleanup, *sockets) }

      context 'single socket passed' do
        let(:sockets) { [sock_a] }

        it 'closes the passed socket' do
          expect(sock_a.closed?).to be_truthy
          expect(sock_b.closed?).to be_falsey
        end
      end

      context 'multiple sockets passed' do
        let(:sockets) { [sock_a, sock_b] }

        it 'closes both sockets' do
          expect(sock_a.closed?).to be_truthy
          expect(sock_b.closed?).to be_truthy
        end
      end
    end

    context 'passed cleanup block' do
      it 'calls the block upon completion' do
        expect { |b| subject.send(:cleanup, *pair, &b) }.to yield_control
      end
    end
  end

  describe '#push' do
    let(:sock_a) { ::UNIXSocket.pair(:DGRAM, 0) }
    let(:sock_b) { ::UNIXSocket.pair(:DGRAM, 0) }

    let(:a_test) { sock_a.first }
    let(:a_proxy) { Celluloid::IO::UNIXSocket.new(sock_a.last) }
    let(:b_test) { sock_b.first }
    let(:b_proxy) { Celluloid::IO::UNIXSocket.new(sock_b.last) }

    let(:str) { 'get schwifty' }

    before { subject.push(a_proxy, b_proxy) }

    describe 'data transmission between two sockets' do
      shared_examples 'transmission' do
        it 'transmits data' do
          left.write_nonblock(str)
          sleep(0.1) # give some time for the transmission
          expect(right.read_nonblock(16)).to eq(str)
        end
      end

      context 'a -> b' do
        let(:left) { a_test }
        let(:right) { b_test }

        include_examples 'transmission'
      end

      context 'b -> a' do
        let(:left) { b_test }
        let(:right) { a_test }

        include_examples 'transmission'
      end
    end

    context 'socket gets closed' do
      before { a_proxy.close }

      it 'its pair gets closed' do
        b_test.write(str)
        sleep(0.1) # give some time for the transmission
        expect(b_proxy).to be_closed
      end
    end
  end
end
