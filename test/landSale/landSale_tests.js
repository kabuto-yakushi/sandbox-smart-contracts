const tap = require('tap');
const assert = require('assert');
const rocketh = require('rocketh');

const {
    tx,
    call,
    gas,
    expectThrow,
    zeroAddress,
    deployContract,
    increaseTime,
} = require('../utils');

const {
    deployer,
    landSaleAdmin,
    landSaleBeneficiary,
    sandBeneficiary,
    landAdmin,
    sandAdmin,
    others,
} = rocketh.namedAccounts;

const MerkleTree = require('../../lib/merkleTree');
const {createDataArray, calculateLandHash} = require('../../lib/merkleTreeHelper');

const testLands = [
    {
        x: 400,
        y: 106,
        size: 1,
        price: '4047',
        reserved: others[1],
        salt: '0x1111111111111111111111111111111111111111111111111111111111111111'
    },
    {
        x: 120,
        y: 144,
        size: 12,
        price: '2773',
        salt: '0x1111111111111111111111111111111111111111111111111111111111111112'
    },
    {
        x: 288,
        y: 144,
        size: 12,
        price: '1358',
        salt: '0x1111111111111111111111111111111111111111111111111111111111111113'
    },
    {
        x: 36,
        y: 114,
        size: 6,
        price: '3169',
        salt: '0x1111111111111111111111111111111111111111111111111111111111111114'
    },
    {
        x: 308,
        y: 282,
        size: 1,
        price: '8465',
        salt: '0x1111111111111111111111111111111111111111111111111111111111111115'
    },
    {
        x: 308,
        y: 281,
        size: 1,
        price: '8465',
        salt: '0x1111111111111111111111111111111111111111111111111111111111111116'
    }
];

const saleStart = Math.floor(Date.now() / 1000);
const saleDuration = 30 * 24 * 60 * 60;
const saleEnd = saleStart + saleDuration;

async function setupTestLandSale(contracts) {
    const landHashArray = createDataArray(testLands);
    const tree = new MerkleTree(landHashArray);
    const contract = await deployContract(
        deployer,
        'LandSale',
        contracts.Land.options.address,
        contracts.Sand.options.address,
        contracts.Sand.options.address,
        landSaleAdmin,
        landSaleBeneficiary,
        tree.getRoot().hash,
        saleEnd
    );
    await tx(contracts.Land, 'setMinter', {from: landAdmin, gas: 1000000}, contract.options.address, true);
    await tx(contracts.Sand, 'setSuperOperator', {from: sandAdmin, gas: 1000000}, contract.options.address, true);
    return {contract, tree};
}

function runLandSaleTests(title, contactStore) {
    tap.test(title + ' tests', async (t) => {
        let contracts;
        let tree;
        let lands;
        let landHashArray;
        t.beforeEach(async () => {
            contracts = await contactStore.resetContracts();
            const deployment = rocketh.deployment('LandSale');
            lands = deployment.data;
            // console.log({lands});
            landHashArray = createDataArray(lands);
            tree = new MerkleTree(landHashArray);
            await tx(contracts.Sand, 'transferFrom', {from: sandBeneficiary, gas}, sandBeneficiary, others[0], '1000000000000000000000000');
            await tx(contracts.Sand, 'transferFrom', {from: sandBeneficiary, gas}, sandBeneficiary, others[1], '1000000000000000000000000');
        });

        t.test('can buy Land', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[0]));
            await tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            );
        });

        t.test('cannot buy Land without enough tokens', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[1]));

            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[2], gas},
                others[2],
                others[2],
                zeroAddress,
                99, 99, 3,
                '17100000000000000000000',
                lands[1].salt,
                proof
            ));
        });

        t.test('cannot buy Land from a non reserved Land with reserved param', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[0]));
            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                others[0],
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            ));
        });

        t.test('cannot buy Land from a reserved Land of a different address', async (t) => {
            const {contract, tree} = await setupTestLandSale(contracts);
            const proof = tree.getProof(calculateLandHash({
                x: 400,
                y: 106,
                size: 1,
                price: '4047',
                reserved: others[1],
                salt: '0x1111111111111111111111111111111111111111111111111111111111111111',
            }));
            await expectThrow(tx(contract, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                others[0],
                400, 106, 1,
                '4047',
                '0x1111111111111111111111111111111111111111111111111111111111111111',
                proof
            ));
        });

        t.test('can buy Land from a reserved Land if matching address', async (t) => {
            const {contract, tree} = await setupTestLandSale(contracts);
            const proof = tree.getProof(calculateLandHash({
                x: 400,
                y: 106,
                size: 1,
                price: '4047',
                reserved: others[1],
                salt: '0x1111111111111111111111111111111111111111111111111111111111111111'
            }));
            await tx(contract, 'buyLandWithSand', {from: others[1], gas},
                others[1],
                others[1],
                others[1],
                400, 106, 1,
                '4047',
                '0x1111111111111111111111111111111111111111111111111111111111111111',
                proof
            );
            const owner = await call(contracts.Land, 'ownerOf', null, 400 + (106 * 408));
            assert.equal(owner, others[1]);
        });

        t.test('can buy Land from a reserved Land and send it to another address', async (t) => {
            const {contract, tree} = await setupTestLandSale(contracts);
            const proof = tree.getProof(calculateLandHash({
                x: 400,
                y: 106,
                size: 1,
                price: '4047',
                reserved: others[1],
                salt: '0x1111111111111111111111111111111111111111111111111111111111111111'
            }));
            await tx(contract, 'buyLandWithSand', {from: others[1], gas},
                others[1],
                others[2],
                others[1],
                400, 106, 1,
                '4047',
                '0x1111111111111111111111111111111111111111111111111111111111111111',
                proof
            );
            const owner = await call(contracts.Land, 'ownerOf', null, 400 + (106 * 408));
            assert.equal(owner, others[2]);
        });

        t.test('CANNOT buy Land when minter rights revoked', async (t) => {
            await tx(contracts.Land, 'setMinter', {from: landAdmin, gas}, contracts.LandSale.options.address, false);
            const proof = tree.getProof(calculateLandHash(lands[0]));
            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            ));
        });

        t.test('CANNOT buy Land twice', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[0]));
            await tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            );
            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            ));
        });

        t.test('CANNOT generate proof for Land not on sale', async (t) => {
            assert.throws(() => tree.getProof(calculateLandHash({
                x: 400,
                y: 106,
                size: 3,
                price: '2000000000000000000000',
                salt: lands[0].salt
            })));
        });

        t.test('CANNOT buy Land with invalid proof', async (t) => {
            const proof = [
                '0x0000000000000000000000000000000000000000000000000000000000000001',
                '0x0000000000000000000000000000000000000000000000000000000000000002',
                '0x0000000000000000000000000000000000000000000000000000000000000003',
            ];
            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            ));
        });

        t.test('CANNOT buy Land with wrong proof', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[2]));
            await expectThrow(tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                400, 106, 1,
                '2000000000000000000000',
                lands[0].salt,
                proof
            ));
        });

        t.test('after buying user own all Land bought', async (t) => {
            const proof = tree.getProof(calculateLandHash(lands[2]));
            await tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                zeroAddress,
                120, 144, 12,
                '244800000000000000000000',
                lands[2].salt,
                proof
            );
            for (let x = 120; x < 120 + 12; x++) {
                for (let y = 144; y < 144 + 12; y++) {
                    const owner = await call(contracts.Land, 'ownerOf', null, x + (y * 408));
                    const balance = await call(contracts.Land, 'balanceOf', null, others[0]);
                    assert.equal(owner, others[0]);
                    assert.equal(balance, 144);
                }
            }
        });

        t.test('can buy all Lands specified in json', async (t) => { // TODO reserved 
            for (const land of lands) {
                const landHash = calculateLandHash(land);
                const proof = tree.getProof(landHash);
                await tx(contracts.LandSale, 'buyLandWithSand', {from: others[0], gas},
                    others[0],
                    others[0],
                    zeroAddress,
                    land.x, land.y, land.size,
                    land.price,
                    land.salt,
                    proof
                );
            }
        });

        t.test('check the expiry time of the sale', async (t) => {
            const {contract} = await setupTestLandSale(contracts);

            const expiryTime = await call(contract, 'getExpiryTime');
            assert.equal(expiryTime, saleEnd, 'Expiry time is wrong');
        });

        t.test('Cannot buy a land after the expiry time', async (t) => {
            await increaseTime(saleDuration);

            const {contract, tree} = await setupTestLandSale(contracts);
            const proof = tree.getProof(calculateLandHash({
                x: 400,
                y: 106,
                size: 1,
                price: '4047',
                reserved: others[1],
                salt: '0x1111111111111111111111111111111111111111111111111111111111111111'
            }));
            await expectThrow(tx(contract, 'buyLandWithSand', {from: others[0], gas},
                others[0],
                others[0],
                others[0],
                400, 106, 1,
                4047,
                '0x1111111111111111111111111111111111111111111111111111111111111111',
                proof
            ));
        });
    });
}

module.exports = {
    runLandSaleTests
};
