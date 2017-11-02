class App < Sinatra::Base
  enable :logging

  SHARED_SECRET = ENV['SHARED_SECRET']

  get '/' do
    'App is runing!'
  end

  post '/webhooks/order' do
    hmac = request.env['HTTP_X_SHOPIFY_HMAC_SHA256']

    request.body.rewind
    data = request.body.read

    halt 403, "You're not authorized to perform this action" unless verify_webhook(hmac, data)

    json_data = JSON.parse data

    gateway = json_data['gateway']
    checkout_id = json_data['checkout_id']
    cancelled_at = json_data['cancelled_at']
    id = json_data['id']

    logger.info({id: id, gateway: gateway, checkout_id: checkout_id, cancelled_at: cancelled_at})

    refund(checkout_id) if gateway == 'mercado_pago'

    return [200, 'Webhook notification received successfully']
  end

  helpers do
    def refund(checkout_id)
      mp = MercadoPago.new(ENV['CLIENT_ID'], ENV['CLIENT_SECRET'])

      response = mp.search_payment(id: nil, site_id: nil, external_reference: checkout_id)['response']

      results = response['results']

      return if results.empty?

      payment = results.first

      payment_id = payment['collection']['id'].to_s

      logger.info mp.refund_payment(payment_id)
    end

    def verify_webhook(hmac, data)
      digest = OpenSSL::Digest.new('sha256')
      calculated_hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, SHARED_SECRET, data)).strip

      hmac == calculated_hmac
    end
  end
end
