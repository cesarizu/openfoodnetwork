Darkswarm.directive "ofnChangeOrderCycle", (OrderCycle, Cart, storage) ->
  # Compares chosen order cycle with pre-set OrderCycle. Will trigger
  # a confirmation if they are different, and Cart isn't empty
  restrict: "A"
  scope: true
  link: (scope, elm, attr)->
    order_cycle_id = ->
      parseInt elm.val()

    cart_needs_emptying = ->
      OrderCycle.order_cycle?.order_cycle_id && OrderCycle.order_cycle.order_cycle_id != order_cycle_id() && !Cart.empty()

    elm.bind 'change', (ev)->
      if cart_needs_emptying()
        if confirm "Are you sure? This will change your selected order cycle and remove any items in your shopping cart."
          Cart.clear()
          scope.changeOrderCycle()
        else
          scope.$apply ->
            scope.revertOrderCycle()
      else
        scope.changeOrderCycle()
