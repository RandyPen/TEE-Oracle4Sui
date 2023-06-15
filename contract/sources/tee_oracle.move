module tee_oracle::oracle {

    use std::string::{Self, String};
    use std::option::{Self, Option};
    use sui::object::{Self, ID, UID};
    use sui::vec_map::{Self, VecMap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::event::emit;

    const TOLERANT_TIME: u64 = 10_000;  // 10 seconds

    // Errors
    const EPriceOutdated: u64 = 0;
    const EUncatalogued: u64 = 1;
    // const EAlreadyExist: u64 = 2;

    struct PriceInfo has copy, drop, store {
        price: u64,
        time: u64,
    }

    struct WriteCap has key {
        id: UID,
    }

    struct Oracle has key, store {
        id: UID,
        admin: ID,
        info: VecMap<String, PriceInfo>,
    }

    struct SetCap has key {
        id: UID,
    }

    struct UpdateSetting has key, store {
        id: UID,
        update_fee: u64,
        tolerant_time: u64,
    }

    // Events
    struct UpdatePrice has copy, drop {
        type: String,
    }

    struct NewCoinSupport has copy, drop {
        type: String,
    }

    struct PriceUpdated has copy, drop {
        type: String,
    }

    fun init(ctx: &mut TxContext) {
        let write_cap = WriteCap { id: object::new(ctx) };
        let set_cap = SetCap { id: object::new(ctx) };
        
        let price_map: VecMap<String, PriceInfo> = vec_map::empty();
        let price_init: PriceInfo = PriceInfo { price: 0, time: 0 };
        vec_map::insert(&mut price_map, string::utf8(b"BTC"), price_init);
        vec_map::insert(&mut price_map, string::utf8(b"ETH"), price_init);
        vec_map::insert(&mut price_map, string::utf8(b"SUI"), price_init);
        vec_map::insert(&mut price_map, string::utf8(b"USDT"), price_init);
        vec_map::insert(&mut price_map, string::utf8(b"USDC"), price_init);

        let oracle = Oracle {
            id: object::new(ctx),
            admin: object::id(&write_cap),
            info: price_map
        };

        let update_setting = UpdateSetting {
            id: object::new(ctx),
            update_fee: 50_000_000,
            tolerant_time: TOLERANT_TIME,
        };

        transfer::public_share_object(oracle);
        transfer::public_share_object(update_setting);
        transfer::transfer(write_cap, tx_context::sender(ctx));
        transfer::transfer(set_cap, @engine);
    }

    public fun update(oracle: &Oracle, update_setting: &UpdateSetting, type: vector<u8>, fee: &mut Coin<SUI>, ctx: &mut TxContext) {
        let symbol: String = string::utf8(type);
        assert!(vec_map::contains(&oracle.info, &symbol), EUncatalogued);
        let fee_coin: Coin<SUI> = coin::split(fee, update_setting.update_fee, ctx);
        transfer::public_transfer(fee_coin, @engine);
        emit( UpdatePrice { type: symbol });
    }

    public fun get_price(oracle: &Oracle, update_setting: &UpdateSetting, type: vector<u8>, clk: &Clock): Option<u64> {
        let symbol: String = string::utf8(type);
        let price_info = vec_map::get(&oracle.info, &symbol);
        let last_update_time = price_info.time;
        let last_price = price_info.price;
        if (clock::timestamp_ms(clk) - last_update_time > update_setting.tolerant_time) {
            return option::none()
        } else {
            return option::some(last_price)
        }
    }

    public fun get_price_unsafe(oracle: &Oracle, type: vector<u8>): u64 {
        let symbol: String = string::utf8(type);
        let price_info = vec_map::get(&oracle.info, &symbol);
        price_info.price
    }

    // Admin Only
    // public entry fun add(oracle: &mut Oracle, _: &WriteCap, type: vector<u8>) {
    //     let symbol: String = string::utf8(type);
    //     assert!(!vec_map::contains(&oracle.info, &symbol), EAlreadyExist);
    //     let price_init: PriceInfo = PriceInfo { price: 0, time: 0 };
    //     vec_map::insert(&mut oracle.info, symbol, price_init);
    //     emit( NewCoinSupport { type: symbol });
    // }

    public entry fun feed_price(oracle: &mut Oracle, _: &WriteCap, type: vector<u8>, price: u64, clk: &Clock) {
        let symbol: String = string::utf8(type);
        // assert!(vec_map::contains(&oracle.info, &symbol), EUncatalogued);
        let price_info = vec_map::get_mut(&mut oracle.info, &symbol);
        price_info.price = price;
        price_info.time = clock::timestamp_ms(clk);
        emit( PriceUpdated { type: symbol });
    }

    public entry fun update_fee(update_setting: &mut UpdateSetting, _: &SetCap, update_fee: u64) {
        update_setting.update_fee = update_fee;
    }

    public entry fun update_tolerant_time(update_setting: &mut UpdateSetting, _: &SetCap, tolerant_time: u64) {
        update_setting.tolerant_time = tolerant_time;
    }
}