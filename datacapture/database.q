/ in the rdb and, at end of day, the hdb
trade:([]time:`timestamp$();sym:`g#`symbol$();price:`float$();size:`long$();side:`symbol$())
quote:([]time:`timestamp$();sym:`g#`symbol$();bid:`float$();ask:`float$();bsize:`long$();asize:`long$())
/ in the idb and, at end of day, the hdb
orders:([]time:`timestamp$();sym:`g#`symbol$();orderid:`long$();side:`symbol$();price:`float$();size:`long$();status:`symbol$())
depth:([]time:`timestamp$();sym:`g#`symbol$();level:`long$();bid:`float$();ask:`float$();bsize:`long$();asize:`long$())
