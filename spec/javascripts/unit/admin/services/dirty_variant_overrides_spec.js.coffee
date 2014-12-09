describe "maintaining a list of dirty variant overrides", ->
  DirtyVariantOverrides = null
  variantOverride =
    variant_id: 1
    hub_id: 2
    price: 3
    count_on_hand: 4

  beforeEach ->
    module "ofn.admin"

  beforeEach inject (_DirtyVariantOverrides_) ->
    DirtyVariantOverrides = _DirtyVariantOverrides_

  it "adds new dirty variant overrides", ->
    DirtyVariantOverrides.add variantOverride
    expect(DirtyVariantOverrides.dirtyVariantOverrides).toEqual
      2:
        1:
          variant_id: 1
          hub_id: 2
          price: 3
          count_on_hand: 4

  it "updates existing dirty variant overrides", ->
    DirtyVariantOverrides.dirtyVariantOverrides =
      2:
        1:
          variant_id: 5
          hub_id: 6
          price: 7
          count_on_hand: 8
    DirtyVariantOverrides.add variantOverride
    expect(DirtyVariantOverrides.dirtyVariantOverrides).toEqual
      2:
        1:
          variant_id: 1
          hub_id: 2
          price: 3
          count_on_hand: 4

  it "counts dirty variant overrides", ->
    DirtyVariantOverrides.dirtyVariantOverrides =
      2:
        1:
          variant_id: 5
          hub_id: 6
          price: 7
          count_on_hand: 8
        3:
          variant_id: 9
          hub_id: 10
          price: 11
          count_on_hand: 12
      4:
        5:
          variant_id: 13
          hub_id: 14
          price: 15
          count_on_hand: 16
    expect(DirtyVariantOverrides.count()).toEqual 3