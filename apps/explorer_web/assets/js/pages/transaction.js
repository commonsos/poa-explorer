import $ from 'jquery'
import socket from '../socket'
import router from '../router'

router.when('/transactions/:transactionHash').then(({ transactionHash }) => {
  const channel = socket.channel(`transactions:${transactionHash}`, {})
  channel.join()
    .receive('ok', resp => { console.log('Joined successfully', `transactions:${transactionHash}`, resp) })
    .receive('error', resp => { console.log('Unable to join', `transactions:${transactionHash}`, resp) })

  const $blockConfirmations = $('[data-selector="block_confirmations"]')
  if ($blockConfirmations.length) {
    channel.on('confirmations', (msg) => {
      $blockConfirmations.empty().append(msg.confirmations)
    })
  }
})
